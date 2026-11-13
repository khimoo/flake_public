package main

import (
	"fmt"
	"github.com/BurntSushi/toml"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"go.starlark.net/resolve"
	"go.starlark.net/starlark"
	"go.starlark.net/syntax"
)

// funcInfo describes one of public/writes/config of an element.
type funcInfo struct {
	params []string        // parameter names in declaration order
	reads  map[string]bool // parameters whose value is read
	writes map[string]bool // parameters named as the first argument of write()
}

type element struct {
	virtual  bool // the host facts element that confgen provides
	name     string
	file     string
	src      []byte
	requires []string
	when     []string
	// needs is checked after the judgments and never makes an element true:
	// a fact the machine lacks must stop the build, not be supplied by the element asking.
	needs []string
	kind  string // "", kindMachine or kindFact
	funcs map[string]*funcInfo
}

const (
	kindMachine = "machine"
	kindFact    = "machine_fact"
)

func (e *element) derived() bool { return len(e.when) > 0 }

// declaresMachine reports whether the element describes the machine rather than what a user does.
func (e *element) declaresMachine() bool { return e.kind != "" }

// refs returns every element this element references (E = R ∪ W ∪ U).
func (e *element) refs() []string {
	set := map[string]bool{}
	for _, r := range e.requires {
		set[r] = true
	}
	for _, f := range e.funcs {
		for _, p := range f.params {
			if p != incomingParam {
				set[p] = true
			}
		}
	}
	return sortedKeys(set)
}

const incomingParam = "incoming"

// hostElement and userElement are provided by confgen, not by files: their public values
// describe the host (system, linux, darwin) and the Home Manager user (name, home) being
// built, so elements need no per-host or per-user flags.
const (
	hostElement     = "host"
	userElement     = "user"
	machinesElement = "machines"
)

var elementFuncs = map[string]bool{"public": true, "writes": true, "config": true, "user_config": true}
var elementLists = map[string]bool{"requires": true, "when": true, "needs": true}
var elementKinds = map[string]bool{kindMachine: true, kindFact: true}
var identRe = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)

func predeclaredNames() map[string]bool {
	return map[string]bool{"pkg": true, "exe": true, "concat": true, "write": true, "struct": true,
		"luaPackages": true, "lua": true, "module": true,
		"repoModule": true, "script": true, "scriptBin": true, "activation": true,
		"inputPkg": true, "file": true, "shellApp": true, "repoPkg": true, "symlinkJoin": true,
		"command": true, "gvariantTuple": true, "outOfStoreLink": true,
		"shellAppEnv": true, "repoText": true, "symlinkJoinBuild": true, "toJSON": true,
		"repoPkgWith": true, "repoPath": true, "pythonWithModules": true,
		"pkgSetFn": true, "pkgWithPackages": true, "mkAfter": true, "mkBefore": true, "flakeRev": true}
}

func fileOptions() *syntax.FileOptions {
	return &syntax.FileOptions{}
}

func loadElements(dir string) (map[string]*element, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.star"))
	if err != nil {
		return nil, err
	}
	elems := map[string]*element{}
	for _, file := range files {
		e, err := parseElement(file)
		if err != nil {
			return nil, err
		}
		elems[e.name] = e
	}
	for _, n := range []string{hostElement, userElement, machinesElement} {
		if _, ok := elems[n]; ok {
			return nil, fmt.Errorf("%s.star: the name %q is reserved for facts confgen provides", n, n)
		}
		elems[n] = &element{virtual: true, name: n, file: "<" + n + " facts>", funcs: map[string]*funcInfo{}}
	}
	if err := checkGraph(elems); err != nil {
		return nil, err
	}
	return elems, nil
}

func parseElement(file string) (*element, error) {
	name := strings.TrimSuffix(filepath.Base(file), ".star")
	if !identRe.MatchString(name) || name == incomingParam {
		return nil, fmt.Errorf("%s: element name %q must match %s and must not be %q", file, name, identRe, incomingParam)
	}
	src, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	f, err := fileOptions().Parse(file, src, 0)
	if err != nil {
		return nil, err
	}
	e := &element{name: name, file: file, src: src, funcs: map[string]*funcInfo{}}

	var defs []*syntax.DefStmt
	for _, stmt := range f.Stmts {
		switch s := stmt.(type) {
		case *syntax.LoadStmt:
			return nil, fmt.Errorf("%s: load is not allowed", s.Load)
		case *syntax.DefStmt:
			n := s.Name.Name
			if !elementFuncs[n] && !strings.HasPrefix(n, "_") {
				return nil, fmt.Errorf("%s: top-level def %q is not allowed (use public, writes, config, user_config or a name starting with _)", s.Def, n)
			}
			if elementFuncs[n] {
				defs = append(defs, s)
			}
		case *syntax.AssignStmt:
			id, ok := s.LHS.(*syntax.Ident)
			if !ok || s.Op != syntax.EQ {
				return nil, fmt.Errorf("%s: only `name = value` is allowed at top level", s.OpPos)
			}
			switch {
			case elementLists[id.Name]:
				list, ok := directStrings(s.RHS)
				if !ok {
					return nil, fmt.Errorf("%s: %s must be a list of string literals", id.NamePos, id.Name)
				}
				switch id.Name {
				case "requires":
					e.requires = list
				case "when":
					e.when = list
				case "needs":
					e.needs = list
				}
			case id.Name == "kind":
				lit, ok := s.RHS.(*syntax.Literal)
				if !ok || lit.Token != syntax.STRING || !elementKinds[lit.Value.(string)] {
					return nil, fmt.Errorf("%s: kind must be %q or %q", id.NamePos, kindMachine, kindFact)
				}
				e.kind = lit.Value.(string)
			case strings.HasPrefix(id.Name, "_"):
			default:
				return nil, fmt.Errorf("%s: top-level name %q is not allowed (use requires, when, needs, kind or a name starting with _)", id.NamePos, id.Name)
			}
		case *syntax.ExprStmt:
			if _, ok := s.X.(*syntax.Literal); !ok {
				start, _ := s.X.Span()
				return nil, fmt.Errorf("%s: top-level expressions are not allowed", start)
			}
		default:
			start, _ := stmt.Span()
			return nil, fmt.Errorf("%s: this statement is not allowed at top level", start)
		}
	}
	if e.declaresMachine() && (len(e.when) > 0 || len(e.needs) > 0) {
		return nil, fmt.Errorf("%s: an element with kind = %q describes the machine and takes no when or needs", file, e.kind)
	}
	if len(e.when) > 0 {
		if len(e.when) < 2 || len(uniq(e.when)) != len(e.when) {
			return nil, fmt.Errorf("%s: when must name at least two distinct elements", file)
		}
	}

	predeclared := predeclaredNames()
	if err := resolve.File(f, func(n string) bool { return predeclared[n] }, starlark.Universe.Has); err != nil {
		return nil, err
	}
	if err := checkWriteUses(f); err != nil {
		return nil, err
	}
	for _, d := range defs {
		info, err := analyzeDef(d)
		if err != nil {
			return nil, err
		}
		e.funcs[d.Name.Name] = info
	}
	return e, nil
}

func directStrings(x syntax.Expr) ([]string, bool) {
	list, ok := x.(*syntax.ListExpr)
	if !ok {
		return nil, false
	}
	var out []string
	for _, item := range list.List {
		lit, ok := item.(*syntax.Literal)
		if !ok || lit.Token != syntax.STRING {
			return nil, false
		}
		out = append(out, lit.Value.(string))
	}
	return out, true
}

// checkWriteUses rejects every use of `write` other than a direct call inside `writes`,
// so the target of a write is always visible in the syntax tree.
func checkWriteUses(f *syntax.File) error {
	var err error
	var walk func(n syntax.Node, inWrites bool)
	walk = func(n syntax.Node, inWrites bool) {
		syntax.Walk(n, func(n syntax.Node) bool {
			if err != nil {
				return false
			}
			switch x := n.(type) {
			case *syntax.DefStmt:
				if x.Name.Name == "writes" {
					for _, s := range x.Body {
						walk(s, true)
					}
					return false
				}
			case *syntax.CallExpr:
				if id, ok := x.Fn.(*syntax.Ident); ok && isPredeclared(id, "write") {
					if !inWrites {
						err = fmt.Errorf("%s: write may only be called inside writes", id.NamePos)
						return false
					}
					for _, a := range x.Args {
						walk(a, inWrites)
					}
					return false
				}
			case *syntax.Ident:
				if isPredeclared(x, "write") {
					err = fmt.Errorf("%s: write may only be called directly", x.NamePos)
					return false
				}
			}
			return true
		})
	}
	for _, s := range f.Stmts {
		walk(s, false)
	}
	return err
}

func isPredeclared(id *syntax.Ident, name string) bool {
	b, ok := id.Binding.(*resolve.Binding)
	return ok && id.Name == name && b.Scope == resolve.Predeclared
}

func analyzeDef(d *syntax.DefStmt) (*funcInfo, error) {
	info := &funcInfo{reads: map[string]bool{}, writes: map[string]bool{}}
	bindings := map[*resolve.Binding]string{}
	for _, p := range d.Params {
		id, ok := p.(*syntax.Ident)
		if !ok {
			return nil, fmt.Errorf("%s: %s: parameters must be plain names", d.Def, d.Name.Name)
		}
		if !identRe.MatchString(id.Name) {
			return nil, fmt.Errorf("%s: parameter %q is not an element name", id.NamePos, id.Name)
		}
		if id.Name == incomingParam && d.Name.Name != "config" && d.Name.Name != "user_config" {
			return nil, fmt.Errorf("%s: only config and user_config may take %s", id.NamePos, incomingParam)
		}
		info.params = append(info.params, id.Name)
		bindings[id.Binding.(*resolve.Binding)] = id.Name
	}

	// Identifiers in these positions create a variable; they are not reads.
	sites := map[*syntax.Ident]bool{}
	// Identifiers that are the target of write(); they are writes, not reads.
	targets := map[*syntax.Ident]bool{}
	var walkErr error
	for _, stmt := range d.Body {
		syntax.Walk(stmt, func(n syntax.Node) bool {
			switch x := n.(type) {
			case *syntax.AssignStmt:
				if x.Op == syntax.EQ {
					markSites(x.LHS, sites)
				}
			case *syntax.ForStmt:
				markSites(x.Vars, sites)
			case *syntax.ForClause:
				markSites(x.Vars, sites)
			case *syntax.DefStmt:
				sites[x.Name] = true
				for _, p := range x.Params {
					markSites(p, sites)
				}
			case *syntax.LambdaExpr:
				for _, p := range x.Params {
					markSites(p, sites)
				}
			case *syntax.CallExpr:
				if id, ok := x.Fn.(*syntax.Ident); ok && isPredeclared(id, "write") {
					if len(x.Args) != 2 {
						walkErr = fmt.Errorf("%s: write takes (element, value)", id.NamePos)
						return false
					}
					t, ok := x.Args[0].(*syntax.Ident)
					var b *resolve.Binding
					if ok {
						b, _ = t.Binding.(*resolve.Binding)
					}
					if !ok || bindings[b] == "" {
						walkErr = fmt.Errorf("%s: the first argument of write must be a parameter of writes", id.NamePos)
						return false
					}
					targets[t] = true
				}
			}
			return true
		})
	}
	if walkErr != nil {
		return nil, walkErr
	}
	for _, stmt := range d.Body {
		syntax.Walk(stmt, func(n syntax.Node) bool {
			id, ok := n.(*syntax.Ident)
			if !ok {
				return true
			}
			b, _ := id.Binding.(*resolve.Binding)
			name := bindings[b]
			switch {
			case name == "" || sites[id]:
			case targets[id]:
				info.writes[name] = true
			default:
				info.reads[name] = true
			}
			return true
		})
	}
	for _, p := range info.params {
		if !info.reads[p] && !info.writes[p] {
			return nil, fmt.Errorf("%s: parameter %q of %s is never read", d.Def, p, d.Name.Name)
		}
	}
	return info, nil
}

func markSites(x syntax.Node, sites map[*syntax.Ident]bool) {
	switch v := x.(type) {
	case *syntax.Ident:
		sites[v] = true
	case *syntax.TupleExpr:
		for _, y := range v.List {
			markSites(y, sites)
		}
	case *syntax.ListExpr:
		for _, y := range v.List {
			markSites(y, sites)
		}
	case *syntax.ParenExpr:
		markSites(v.X, sites)
	case *syntax.BinaryExpr:
		// default value of a parameter: `x=default`; only the name creates a variable.
		if v.Op == syntax.EQ {
			markSites(v.X, sites)
		}
	case *syntax.UnaryExpr:
		// *args, **kwargs
		markSites(v.X, sites)
	}
}

func checkGraph(elems map[string]*element) error {
	for _, e := range sortedElems(elems) {
		for _, r := range e.refs() {
			t, ok := elems[r]
			if !ok {
				return fmt.Errorf("%s: unknown element %q", e.file, r)
			}
			if t.derived() {
				return fmt.Errorf("%s: %q is a derived element and must not be referenced", e.file, r)
			}
			if t.kind == kindMachine {
				return fmt.Errorf("%s: %q is a machine element; only the machine key of a host file selects it", e.file, r)
			}
			// An action that requires a fact would make the fact true wherever the action is chosen.
			if t.declaresMachine() && !e.declaresMachine() {
				return fmt.Errorf("%s: %q describes the machine; only machine elements and other machine facts may require it. Name it in when or needs instead", e.file, r)
			}
		}
		for _, w := range e.when {
			t, ok := elems[w]
			if !ok {
				return fmt.Errorf("%s: unknown element %q in when", e.file, w)
			}
			// A machine name in when ties the element to one host; name the fact that makes it work.
			if t.kind == kindMachine {
				return fmt.Errorf("%s: when names the machine element %q; name a machine fact that the machine element requires", e.file, w)
			}
		}
		for _, n := range e.needs {
			t, ok := elems[n]
			if !ok {
				return fmt.Errorf("%s: unknown element %q in needs", e.file, n)
			}
			if t.virtual {
				return fmt.Errorf("%s: %q is provided by confgen and cannot be in needs", e.file, n)
			}
		}
	}
	return nil
}

// selectablePurpose checks one name in a user's purposes. A host with a machine element gets
// the machine's facts from that element; only hosts without one (the hosts under
// tests/) list them in purposes.
func selectablePurpose(file string, elems map[string]*element, name string, hasMachine bool) error {
	if err := selectable(file, elems, name); err != nil {
		return err
	}
	e := elems[name]
	if e.kind == kindMachine {
		return fmt.Errorf("%s: %q is a machine element; write it as machine = %q", file, name, name)
	}
	if e.declaresMachine() && hasMachine {
		return fmt.Errorf("%s: %q describes the machine; require it from the machine element instead of listing it in purposes", file, name)
	}
	return nil
}

// hostSpec is one config/hosts/<host>.toml: the machine element, the users with the
// purposes each user selects, and the other keys, which become host facts (host.<key>).
// flake.nix reads the same file for the host's structure (system, users), so each value
// about a host lives in one place.
type hostSpec struct {
	machine string
	users   []userSpec
	values  starlark.StringDict
}

// userSpec is one [[users]] entry. Its keys other than name and purposes become user
// facts (user.<key>) next to the keys of config/users/<name>.toml.
type userSpec struct {
	name     string
	purposes []string
	values   starlark.StringDict
}

func loadHost(file string, elems map[string]*element) (*hostSpec, error) {
	values, err := loadTOML(file)
	if err != nil {
		return nil, err
	}
	if _, ok := values["purposes"]; ok {
		return nil, fmt.Errorf("%s: purposes belongs to each [[users]] entry, not to the host", file)
	}
	for _, k := range []string{"linux", "darwin"} {
		if _, ok := values[k]; ok {
			return nil, fmt.Errorf("%s: %s is set by confgen", file, k)
		}
	}
	spec := &hostSpec{}
	if raw, ok := values["machine"]; ok {
		name, ok := raw.(starlark.String)
		if !ok {
			return nil, fmt.Errorf("%s: machine must be an element name", file)
		}
		if err := selectable(file, elems, string(name)); err != nil {
			return nil, err
		}
		if elems[string(name)].kind != kindMachine {
			return nil, fmt.Errorf("%s: machine must name an element with kind = %q, but %q has none", file, kindMachine, string(name))
		}
		spec.machine = string(name)
		delete(values, "machine")
	}
	list, ok := values["users"].(*starlark.List)
	if !ok || list.Len() == 0 {
		return nil, fmt.Errorf("%s: users must list at least one [[users]] entry", file)
	}
	seen := map[string]bool{}
	for i := 0; i < list.Len(); i++ {
		entry, ok := list.Index(i).(*starlark.Dict)
		if !ok {
			return nil, fmt.Errorf("%s: each users entry must be a table", file)
		}
		u := userSpec{values: starlark.StringDict{}}
		for _, item := range entry.Items() {
			k := string(item[0].(starlark.String))
			switch k {
			case "name":
				n, ok := item[1].(starlark.String)
				if !ok {
					return nil, fmt.Errorf("%s: users.name must be a string", file)
				}
				u.name = string(n)
			case "purposes":
				l, ok := item[1].(*starlark.List)
				if !ok {
					return nil, fmt.Errorf("%s: purposes must be a list of element names", file)
				}
				u.purposes = []string{}
				for j := 0; j < l.Len(); j++ {
					name, ok := l.Index(j).(starlark.String)
					if !ok {
						return nil, fmt.Errorf("%s: purposes must be a list of element names", file)
					}
					if err := selectablePurpose(file, elems, string(name), spec.machine != ""); err != nil {
						return nil, err
					}
					u.purposes = append(u.purposes, string(name))
				}
			default:
				u.values[k] = item[1]
			}
		}
		if u.name == "" {
			return nil, fmt.Errorf("%s: each users entry needs a name", file)
		}
		if seen[u.name] {
			return nil, fmt.Errorf("%s: user %q is listed twice", file, u.name)
		}
		seen[u.name] = true
		if u.purposes == nil {
			return nil, fmt.Errorf("%s: user %s has no purposes (write purposes = [] to select none)", file, u.name)
		}
		spec.users = append(spec.users, u)
	}
	values["users"] = withoutPurposes(list)
	spec.values = values
	return spec, nil
}

// selectable rejects names that cannot be an axiom: unknown elements, and derived elements,
// which may enter only when everything in their when is true.
func selectable(file string, elems map[string]*element, name string) error {
	e, found := elems[name]
	if !found {
		return fmt.Errorf("%s: unknown element %q", file, name)
	}
	if e.derived() {
		return fmt.Errorf("%s: derived element %q cannot be selected", file, name)
	}
	if e.virtual {
		return fmt.Errorf("%s: %q is provided by confgen and cannot be selected", file, name)
	}
	return nil
}

// withoutPurposes copies the [[users]] list without purposes. Elements receive the users
// as values; a purpose is a judgment, which elements must not read (rule A).
func withoutPurposes(list *starlark.List) *starlark.List {
	var items []starlark.Value
	for i := 0; i < list.Len(); i++ {
		entry, ok := list.Index(i).(*starlark.Dict)
		if !ok {
			items = append(items, list.Index(i))
			continue
		}
		d := starlark.NewDict(entry.Len())
		for _, item := range entry.Items() {
			if item[0] != starlark.String("purposes") {
				d.SetKey(item[0], item[1])
			}
		}
		items = append(items, d)
	}
	return starlark.NewList(items)
}

// loadMachines reads every host file, so elements that configure links between machines
// (ssh, remote builds) can read all of them as machines.all[<host>]. The purposes of the
// users and the machine element are left out for the same reason as in withoutPurposes.
func loadMachines(dir string) (starlark.StringDict, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.toml"))
	if err != nil {
		return nil, err
	}
	all := starlark.NewDict(len(files))
	for _, f := range files {
		v, err := loadTOML(f)
		if err != nil {
			return nil, err
		}
		d := starlark.NewDict(len(v))
		for _, k := range sortedKeys(v) {
			switch k {
			case "purposes", "machine":
				continue
			case "users":
				if l, ok := v[k].(*starlark.List); ok {
					d.SetKey(starlark.String(k), withoutPurposes(l))
					continue
				}
			}
			d.SetKey(starlark.String(k), v[k])
		}
		all.SetKey(starlark.String(strings.TrimSuffix(filepath.Base(f), ".toml")), d)
	}
	return starlark.StringDict{"all": all}, nil
}

func loadTOML(file string) (starlark.StringDict, error) {
	var raw map[string]any
	if _, err := toml.DecodeFile(file, &raw); err != nil {
		return nil, err
	}
	out := starlark.StringDict{}
	for k, v := range raw {
		sv, err := fromTOML(v)
		if err != nil {
			return nil, fmt.Errorf("%s: %s: %w", file, k, err)
		}
		out[k] = sv
	}
	return out, nil
}

func fromTOML(v any) (starlark.Value, error) {
	switch x := v.(type) {
	case string:
		return starlark.String(x), nil
	case bool:
		return starlark.Bool(x), nil
	case int64:
		return starlark.MakeInt64(x), nil
	case float64:
		return starlark.Float(x), nil
	case []any:
		var items []starlark.Value
		for _, y := range x {
			sv, err := fromTOML(y)
			if err != nil {
				return nil, err
			}
			items = append(items, sv)
		}
		return starlark.NewList(items), nil
	case []map[string]any:
		var items []starlark.Value
		for _, y := range x {
			sv, err := fromTOML(y)
			if err != nil {
				return nil, err
			}
			items = append(items, sv)
		}
		return starlark.NewList(items), nil
	case map[string]any:
		d := starlark.NewDict(len(x))
		for _, k := range sortedKeys(x) {
			sv, err := fromTOML(x[k])
			if err != nil {
				return nil, err
			}
			d.SetKey(starlark.String(k), sv)
		}
		return d, nil
	}
	return nil, fmt.Errorf("unsupported TOML value %T", v)
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func sortedElems(m map[string]*element) []*element {
	var out []*element
	for _, k := range sortedKeys(m) {
		out = append(out, m[k])
	}
	return out
}

func uniq(xs []string) []string {
	set := map[string]bool{}
	for _, x := range xs {
		set[x] = true
	}
	return sortedKeys(set)
}

// loadUserFile reads config/users/<user>.toml; its keys become user facts (user.<key>).
// A missing file is empty.
func loadUserFile(file string) (starlark.StringDict, error) {
	if _, err := os.Stat(file); os.IsNotExist(err) {
		return starlark.StringDict{}, nil
	}
	values, err := loadTOML(file)
	if err != nil {
		return nil, err
	}
	for _, k := range []string{"name", "home"} {
		if _, ok := values[k]; ok {
			return nil, fmt.Errorf("%s: %s is set by confgen", file, k)
		}
	}
	return values, nil
}
