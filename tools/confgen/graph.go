package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"

	"go.starlark.net/starlark"
)

//go:embed graph.html
var graphPage string

type graphData struct {
	Hosts []graphHost `json:"hosts"`
}

type graphHost struct {
	Name   string `json:"name"`
	System string `json:"system"`
	// NixOS holds each element's NixOS settings once per host, because NixOS has one
	// configuration for all users.
	NixOS map[string][]graphSetting `json:"nixos"`
	Users []graphUser               `json:"users"`
}

type graphUser struct {
	Name  string      `json:"name"`
	Nodes []graphNode `json:"nodes"`
	Edges []graphEdge `json:"edges"`
}

type graphNode struct {
	ID   string         `json:"id"`
	Role string         `json:"role"` // "purpose", "machine", "fact" or ""
	Home []graphSetting `json:"home"`
}

type graphEdge struct {
	From string `json:"from"`
	To   string `json:"to"`
	Kind string `json:"kind"` // "requires", "reads" or "writes"
}

type graphSetting struct {
	Path  string `json:"path"`
	Value string `json:"value"`
}

func configGraph(dir string) (*graphData, error) {
	data := &graphData{Hosts: []graphHost{}}
	err := forEachGraphHost(dir, func(elems map[string]*element, spec *hostSpec, r *hostResult) error {
		h := graphHost{Name: r.Host, System: r.System, NixOS: map[string][]graphSetting{}, Users: []graphUser{}}
		for element, out := range r.Elements {
			settings, err := graphSettings(out, "nixos")
			if err != nil {
				return fmt.Errorf("%s: %s: %w", r.Host, element, err)
			}
			if len(settings) > 0 {
				h.NixOS[element] = settings
			}
		}
		for _, u := range spec.users {
			gu, err := graphUserOf(elems, r, u.name)
			if err != nil {
				return fmt.Errorf("%s: %s: %w", r.Host, u.name, err)
			}
			h.Users = append(h.Users, gu)
		}
		data.Hosts = append(data.Hosts, h)
		return nil
	})
	if err != nil {
		return nil, err
	}
	return data, nil
}

func forEachGraphHost(dir string, visit func(map[string]*element, *hostSpec, *hostResult) error) error {
	elems, err := loadElements(filepath.Join(dir, "elements"))
	if err != nil {
		return err
	}
	files, err := filepath.Glob(filepath.Join(dir, "hosts", "*.toml"))
	if err != nil {
		return err
	}
	sort.Strings(files)
	for _, file := range files {
		spec, err := loadHost(file, elems)
		if err != nil {
			return err
		}
		system, ok := spec.values["system"].(starlark.String)
		if !ok || system == "" {
			return fmt.Errorf("%s: system must be a non-empty string", file)
		}
		name := strings.TrimSuffix(filepath.Base(file), ".toml")
		r, err := buildHost(dir, name, string(system))
		if err != nil {
			return err
		}
		if err := visit(elems, spec, r); err != nil {
			return err
		}
	}
	return nil
}

func graphShowsElement(elems map[string]*element, name string) bool {
	e, ok := elems[name]
	return ok && !e.virtual
}

func graphUserOf(elems map[string]*element, r *hostResult, user string) (graphUser, error) {
	u := r.Users[user]
	gu := graphUser{Name: user, Nodes: []graphNode{}, Edges: []graphEdge{}}
	for _, name := range sortedKeys(u.Reasons) {
		if !graphShowsElement(elems, name) {
			continue
		}
		home, err := graphSettings(u.Elements[name], "home")
		if err != nil {
			return gu, fmt.Errorf("%s: %w", name, err)
		}
		gu.Nodes = append(gu.Nodes, graphNode{ID: name, Role: graphRole(elems[name], u.Reasons[name]), Home: home})
		g := r.Graph[name]
		for _, kind := range []struct {
			name    string
			targets []string
		}{{"requires", g.Requires}, {"reads", g.Reads}, {"writes", g.Writes}} {
			for _, target := range kind.targets {
				if graphShowsElement(elems, target) {
					gu.Edges = append(gu.Edges, graphEdge{From: name, To: target, Kind: kind.name})
				}
			}
		}
	}
	return gu, nil
}

func graphRole(e *element, rs reason) string {
	switch {
	case rs.Axiom == "purposes":
		return "purpose"
	case rs.Axiom == "machine":
		return "machine"
	case e.kind == kindFact:
		return "fact"
	}
	return ""
}

func graphSettings(out outputs, class string) ([]graphSetting, error) {
	result := []graphSetting{}
	imports, _ := out[class+"_imports"].([]any)
	for _, m := range imports {
		value, err := graphDisplay(m)
		if err != nil {
			return nil, err
		}
		result = append(result, graphSetting{Path: "import", Value: value})
	}
	settings, _ := out[class].([]setting)
	for _, s := range settings {
		value, err := graphDisplay(s.Value)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", strings.Join(s.Path, "."), err)
		}
		result = append(result, graphSetting{Path: graphOptionPath(s.Path), Value: value})
	}
	return result, nil
}

// graphDisplay writes a value the way an element writes it in Starlark, on one line when it
// is short and one item per line otherwise.
func graphDisplay(v any) (string, error) {
	line, err := graphValue(v, false, 0)
	if err != nil {
		return "", err
	}
	if utf8.RuneCountInString(line) <= 80 && !graphHasNewline(v) {
		return line, nil
	}
	return graphValue(v, true, 0)
}

var graphPlainAttr = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_'-]*$`)

// graphOptionPath quotes the parts that are not plain attribute names, as Nix does, so that a
// part like ".local/share/x.desktop" stays one part when the parts are joined with dots.
func graphOptionPath(path []string) string {
	parts := make([]string, len(path))
	for i, part := range path {
		if graphPlainAttr.MatchString(part) {
			parts[i] = part
		} else {
			parts[i] = strconv.Quote(part)
		}
	}
	return strings.Join(parts, ".")
}

func graphHasNewline(v any) bool {
	switch x := v.(type) {
	case string:
		return strings.ContainsAny(x, "\r\n")
	case []any:
		for _, v := range x {
			if graphHasNewline(v) {
				return true
			}
		}
	case map[string]any:
		for k, v := range x {
			if strings.ContainsAny(k, "\r\n") || graphHasNewline(v) {
				return true
			}
		}
	}
	return false
}

func graphValue(v any, multiline bool, depth int) (string, error) {
	switch x := v.(type) {
	case nil:
		return "None", nil
	case string:
		if multiline && strings.ContainsAny(x, "\r\n") {
			return "''\n" + x + "\n" + strings.Repeat("  ", depth) + "''", nil
		}
		return strconv.Quote(x), nil
	case bool:
		if x {
			return "True", nil
		}
		return "False", nil
	case int:
		return strconv.Itoa(x), nil
	case int64:
		return strconv.FormatInt(x, 10), nil
	case float64:
		return strconv.FormatFloat(x, 'g', -1, 64), nil
	case []any:
		parts := []string{}
		for _, item := range x {
			s, err := graphValue(item, multiline, depth+1)
			if err != nil {
				return "", err
			}
			parts = append(parts, s)
		}
		return graphCollection("[", "]", parts, multiline, depth), nil
	case map[string]any:
		if len(x) == 1 {
			for k, value := range x {
				if strings.HasPrefix(k, "$") {
					return graphMarker(k, value, multiline, depth)
				}
			}
		}
		parts := []string{}
		for _, k := range sortedKeys(x) {
			s, err := graphValue(x[k], multiline, depth+1)
			if err != nil {
				return "", err
			}
			parts = append(parts, strconv.Quote(k)+": "+s)
		}
		return graphCollection("{", "}", parts, multiline, depth), nil
	}
	return "", fmt.Errorf("unsupported value %T", v)
}

// graphMarker writes a helper value (see nixMarker) as the helper call that made it.
func graphMarker(kind string, value any, multiline bool, depth int) (string, error) {
	var args []any
	switch kind {
	case "$pkg", "$lua", "$luaPackages", "$concat", "$repoModule":
		args = []any{value}
	default:
		list, ok := value.([]any)
		if !ok {
			return "", fmt.Errorf("%s arguments must be a list", kind)
		}
		args = list
	}
	parts := []string{}
	for _, arg := range args {
		s, err := graphValue(arg, multiline, depth)
		if err != nil {
			return "", err
		}
		parts = append(parts, s)
	}
	return strings.TrimPrefix(kind, "$") + "(" + strings.Join(parts, ", ") + ")", nil
}

func graphCollection(open, close string, parts []string, multiline bool, depth int) string {
	if !multiline || len(parts) == 0 {
		return open + strings.Join(parts, ", ") + close
	}
	indent := strings.Repeat("  ", depth)
	return open + "\n" + indent + "  " + strings.Join(parts, ",\n"+indent+"  ") + "\n" + indent + close
}

type graphOption struct {
	Display string   `json:"display"`
	Parts   []string `json:"parts"`
}

type graphHostOptions struct {
	NixOS []graphOption            `json:"nixos"`
	Users map[string][]graphOption `json:"users"`
}

func graphOptions(dir string) (map[string]graphHostOptions, error) {
	result := map[string]graphHostOptions{}
	err := forEachGraphHost(dir, func(elems map[string]*element, spec *hostSpec, r *hostResult) error {
		host := graphHostOptions{
			NixOS: graphOptionPairs(r.Elements, sortedKeys(r.Elements), "nixos"),
			Users: map[string][]graphOption{},
		}
		for _, u := range spec.users {
			user := r.Users[u.name]
			names := []string{}
			for _, name := range sortedKeys(user.Reasons) {
				if graphShowsElement(elems, name) {
					names = append(names, name)
				}
			}
			host.Users[u.name] = graphOptionPairs(user.Elements, names, "home")
		}
		result[r.Host] = host
		return nil
	})
	return result, err
}

func graphOptionPairs(elements map[string]outputs, names []string, class string) []graphOption {
	pairs := []graphOption{}
	seen := map[string]bool{}
	for _, name := range names {
		settings, _ := elements[name][class].([]setting)
		for _, s := range settings {
			display := graphOptionPath(s.Path)
			if display == "import" || seen[display] {
				continue
			}
			pairs = append(pairs, graphOption{Display: display, Parts: s.Path})
			seen[display] = true
		}
	}
	return pairs
}

type graphPageData struct {
	Hosts     []graphHost       `json:"hosts"`
	Final     json.RawMessage   `json:"final"`
	Sources   map[string]string `json:"sources"`
	Declaring map[string]string `json:"declaring"`
}

type graphDeclarations map[string]struct {
	Positions []struct {
		File string `json:"file"`
	} `json:"positions"`
}

func graphDeclaringSources(final []byte) (map[string]string, error) {
	var hosts map[string]struct {
		Declarations struct {
			NixOS graphDeclarations            `json:"nixos"`
			Users map[string]graphDeclarations `json:"users"`
		} `json:"declarations"`
	}
	if err := json.Unmarshal(final, &hosts); err != nil {
		return nil, err
	}
	paths := map[string]bool{}
	addPaths := func(group graphDeclarations) {
		for _, declaration := range group {
			for _, position := range declaration.Positions {
				paths[position.File] = true
			}
		}
	}
	for _, host := range hosts {
		addPaths(host.Declarations.NixOS)
		for _, group := range host.Declarations.Users {
			addPaths(group)
		}
	}
	files := map[string]string{}
	for path := range paths {
		if raw, err := os.ReadFile(path); err == nil {
			files[path] = string(raw)
		}
	}
	return files, nil
}

func graphConfigSources(dir string) (map[string]string, error) {
	files := map[string]string{}
	for _, pattern := range []string{"hosts/*.toml", "elements/*.star"} {
		paths, err := filepath.Glob(filepath.Join(dir, pattern))
		if err != nil {
			return nil, err
		}
		for _, path := range paths {
			raw, err := os.ReadFile(path)
			if err != nil {
				return nil, err
			}
			key := "config/" + filepath.Dir(pattern) + "/" + filepath.Base(path)
			files[key] = string(raw)
		}
	}
	return files, nil
}

func writeGraph(dir, finalPath, path string) error {
	final, err := os.ReadFile(finalPath)
	if err != nil {
		return err
	}
	declaring, err := graphDeclaringSources(final)
	if err != nil {
		return fmt.Errorf("%s: %w", finalPath, err)
	}
	data, err := configGraph(dir)
	if err != nil {
		return err
	}
	sources, err := graphConfigSources(dir)
	if err != nil {
		return err
	}
	// json.Marshal escapes <, > and &, so no value can close the script element early.
	encoded, err := json.Marshal(graphPageData{
		Hosts: data.Hosts, Final: final, Sources: sources, Declaring: declaring,
	})
	if err != nil {
		return err
	}
	return os.WriteFile(path, []byte(strings.Replace(graphPage, "{{DATA}}", string(encoded), 1)), 0o644)
}
