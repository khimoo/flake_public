package main

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"go.starlark.net/starlark"
	"go.starlark.net/starlarkstruct"
	"go.starlark.net/syntax"
)

// generated computes the least set closed under the reference and condition rules.
func generated(elems map[string]*element, purposes []string) map[string]bool {
	g := map[string]bool{}
	for _, p := range purposes {
		g[p] = true
	}
	for changed := true; changed; {
		changed = false
		for _, e := range sortedElems(elems) {
			if g[e.name] {
				for _, r := range e.refs() {
					if !g[r] {
						g[r] = true
						changed = true
					}
				}
				continue
			}
			if e.derived() && allIn(e.when, g) {
				g[e.name] = true
				changed = true
			}
		}
	}
	return g
}

func allIn(xs []string, set map[string]bool) bool {
	for _, x := range xs {
		if !set[x] {
			return false
		}
	}
	return true
}

// elementRef is what a parameter receives: the referenced element's public values.
// Starlark code cannot construct one, so write() can only target a declared parameter.
type elementRef struct {
	name   string
	public *starlarkstruct.Struct
}

func (r *elementRef) String() string        { return "<element " + r.name + ">" }
func (r *elementRef) Type() string          { return "element" }
func (r *elementRef) Freeze()               {}
func (r *elementRef) Truth() starlark.Bool  { return starlark.True }
func (r *elementRef) Hash() (uint32, error) { return 0, fmt.Errorf("element is not hashable") }
func (r *elementRef) Attr(n string) (starlark.Value, error) {
	return r.public.Attr(n)
}
func (r *elementRef) AttrNames() []string { return r.public.AttrNames() }

type writeRecord struct {
	target string
	value  starlark.Value
}

func (w *writeRecord) String() string        { return "<write to " + w.target + ">" }
func (w *writeRecord) Type() string          { return "write" }
func (w *writeRecord) Freeze()               { w.value.Freeze() }
func (w *writeRecord) Truth() starlark.Bool  { return starlark.True }
func (w *writeRecord) Hash() (uint32, error) { return 0, fmt.Errorf("write is not hashable") }

// marker stands for a value only Nix can build. Its String form is a sentinel that
// the output check rejects, so a marker turned into text by str() or format() fails
// instead of silently losing the store path.
type marker struct {
	json any
	text string
}

const markerSentinel = "<confgen-marker:"

func (m *marker) String() string        { return markerSentinel + m.text + ">" }
func (m *marker) Type() string          { return "marker" }
func (m *marker) Freeze()               {}
func (m *marker) Truth() starlark.Bool  { return starlark.True }
func (m *marker) Hash() (uint32, error) { return 0, fmt.Errorf("marker is not hashable") }

// CompareSameType makes two markers for the same Nix value equal, so `p not in packages`
// removes duplicates the way lib.unique does on the Nix side.
func (m *marker) CompareSameType(op syntax.Token, y starlark.Value, _ int) (bool, error) {
	a, _ := json.Marshal(m.json)
	b, _ := json.Marshal(y.(*marker).json)
	switch op {
	case syntax.EQL:
		return string(a) == string(b), nil
	case syntax.NEQ:
		return string(a) != string(b), nil
	}
	return false, fmt.Errorf("markers only support == and !=")
}

func builtins() starlark.StringDict {
	pkg := starlark.NewBuiltin("pkg", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
		var name string
		if err := starlark.UnpackPositionalArgs(b.Name(), args, kw, 1, &name); err != nil {
			return nil, err
		}
		return &marker{json: map[string]any{"$pkg": name}, text: "pkg " + name}, nil
	})
	exe := starlark.NewBuiltin("exe", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
		var p, bin string
		if err := starlark.UnpackPositionalArgs(b.Name(), args, kw, 2, &p, &bin); err != nil {
			return nil, err
		}
		return &marker{json: map[string]any{"$exe": []any{p, bin}}, text: "exe " + p + "/" + bin}, nil
	})
	concat := starlark.NewBuiltin("concat", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
		if len(kw) > 0 {
			return nil, fmt.Errorf("concat takes no keyword arguments")
		}
		var parts []any
		for _, a := range args {
			switch v := a.(type) {
			case starlark.String:
				parts = append(parts, string(v))
			case *marker:
				if inner, ok := v.json.(map[string]any)["$concat"]; ok {
					parts = append(parts, inner.([]any)...)
				} else {
					parts = append(parts, v.json)
				}
			default:
				return nil, fmt.Errorf("concat: got %s, want string or marker", a.Type())
			}
		}
		return &marker{json: map[string]any{"$concat": parts}, text: "concat"}, nil
	})
	write := starlark.NewBuiltin("write", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
		if len(args) != 2 || len(kw) > 0 {
			return nil, fmt.Errorf("write takes (element, value)")
		}
		ref, ok := args[0].(*elementRef)
		if !ok {
			return nil, fmt.Errorf("write: got %s, want an element parameter", args[0].Type())
		}
		return &writeRecord{target: ref.name, value: args[1]}, nil
	})
	luaPackages := starlark.NewBuiltin("luaPackages", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
		var names *starlark.List
		if err := starlark.UnpackPositionalArgs(b.Name(), args, kw, 1, &names); err != nil {
			return nil, err
		}
		out := []any{}
		for i := 0; i < names.Len(); i++ {
			s, ok := names.Index(i).(starlark.String)
			if !ok {
				return nil, fmt.Errorf("luaPackages: names must be strings")
			}
			out = append(out, string(s))
		}
		return &marker{json: map[string]any{"$luaPackages": out}, text: "luaPackages"}, nil
	})
	module := starlark.NewBuiltin("module", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
		var input, attr string
		if err := starlark.UnpackPositionalArgs(b.Name(), args, kw, 2, &input, &attr); err != nil {
			return nil, err
		}
		return &marker{json: map[string]any{"$module": []any{input, attr}}, text: "module " + input + "#" + attr}, nil
	})
	strArg := func(name string, args starlark.Tuple, kw []starlark.Tuple, n int) ([]string, error) {
		vals := make([]string, n)
		ptrs := make([]any, n)
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		return vals, starlark.UnpackPositionalArgs(name, args, kw, n, ptrs...)
	}
	textArg := func(name string, v starlark.Value) (any, error) {
		switch x := v.(type) {
		case starlark.String:
			return string(x), nil
		case *marker:
			return x.json, nil
		}
		return nil, fmt.Errorf("%s: text must be a string or concat(...)", name)
	}
	inputPkg := starlark.NewBuiltin("inputPkg", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
		v, err := strArg(b.Name(), args, kw, 2)
		if err != nil {
			return nil, err
		}
		return &marker{json: map[string]any{"$inputPkg": []any{v[0], v[1]}}, text: "inputPkg " + v[0] + "#" + v[1]}, nil
	})
	file := starlark.NewBuiltin("file", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
		if len(args) != 2 || len(kw) > 0 {
			return nil, fmt.Errorf("file takes (name, text)")
		}
		name, ok := args[0].(starlark.String)
		if !ok {
			return nil, fmt.Errorf("file: name must be a string")
		}
		text, err := textArg("file", args[1])
		if err != nil {
			return nil, err
		}
		return &marker{json: map[string]any{"$file": []any{string(name), text}}, text: "file " + string(name)}, nil
	})
	// generic wraps a builder whose arguments are already JSON-able values (strings, lists,
	// markers): the bridge calls the matching Nix function with them.
	generic := func(kind string, n int) *starlark.Builtin {
		return starlark.NewBuiltin(kind, func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
			if len(args) != n || len(kw) > 0 {
				return nil, fmt.Errorf("%s takes %d arguments", kind, n)
			}
			vals := []any{}
			for _, a := range args {
				j, err := toJSON(a)
				if err != nil {
					return nil, fmt.Errorf("%s: %w", kind, err)
				}
				vals = append(vals, j)
			}
			return &marker{json: map[string]any{"$" + kind: vals}, text: kind}, nil
		})
	}
	repoModule := starlark.NewBuiltin("repoModule", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
		v, err := strArg(b.Name(), args, kw, 1)
		if err != nil {
			return nil, err
		}
		return &marker{json: map[string]any{"$repoModule": v[0]}, text: "repoModule " + v[0]}, nil
	})
	script := func(kind string) *starlark.Builtin {
		return starlark.NewBuiltin(kind, func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
			if len(args) != 2 || len(kw) > 0 {
				return nil, fmt.Errorf("%s takes (name, text)", kind)
			}
			name, ok := args[0].(starlark.String)
			if !ok {
				return nil, fmt.Errorf("%s: name must be a string", kind)
			}
			text, err := textArg(kind, args[1])
			if err != nil {
				return nil, err
			}
			return &marker{json: map[string]any{"$" + kind: []any{string(name), text}}, text: kind + " " + string(name)}, nil
		})
	}
	activation := starlark.NewBuiltin("activation", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
		var after *starlark.List
		var body starlark.Value
		if err := starlark.UnpackPositionalArgs(b.Name(), args, kw, 2, &after, &body); err != nil {
			return nil, err
		}
		names := []any{}
		for i := 0; i < after.Len(); i++ {
			s, ok := after.Index(i).(starlark.String)
			if !ok {
				return nil, fmt.Errorf("activation: after must be a list of strings")
			}
			names = append(names, string(s))
		}
		text, err := textArg("activation", body)
		if err != nil {
			return nil, err
		}
		return &marker{json: map[string]any{"$activation": []any{names, text}}, text: "activation"}, nil
	})
	lua := starlark.NewBuiltin("lua", func(_ *starlark.Thread, b *starlark.Builtin, args starlark.Tuple, kw []starlark.Tuple) (starlark.Value, error) {
		if len(args) != 1 || len(kw) > 0 {
			return nil, fmt.Errorf("lua takes one value")
		}
		j, err := toJSON(args[0])
		if err != nil {
			return nil, fmt.Errorf("lua: %w", err)
		}
		return &marker{json: map[string]any{"$lua": j}, text: "lua"}, nil
	})
	return starlark.StringDict{
		"pkg": pkg, "exe": exe, "concat": concat, "write": write,
		"luaPackages": luaPackages, "lua": lua, "module": module,
		"repoModule": repoModule, "script": script("script"), "scriptBin": script("scriptBin"),
		"outOfStoreLink": generic("outOfStoreLink", 1),
		"activation": activation, "inputPkg": inputPkg, "file": file,
		"shellApp": generic("shellApp", 3), "shellAppEnv": generic("shellAppEnv", 4),
		"repoPkg": generic("repoPkg", 1), "repoText": generic("repoText", 1),
		"symlinkJoin": generic("symlinkJoin", 2), "symlinkJoinBuild": generic("symlinkJoinBuild", 4),
		"toJSON": generic("toJSON", 1), "pkgSetFn": generic("pkgSetFn", 1),
		"pkgWithPackages": generic("pkgWithPackages", 2),
		"mkAfter": generic("mkAfter", 1), "mkBefore": generic("mkBefore", 1),
		"flakeRev": generic("flakeRev", 0), "repoPkgWith": generic("repoPkgWith", 2),
		"repoPath": generic("repoPath", 1), "pythonWithModules": generic("pythonWithModules", 1), "command": generic("command", 2),
		"gvariantTuple": generic("gvariantTuple", 1),
		"struct": starlark.NewBuiltin("struct", starlarkstruct.Make),
	}
}

type hostResult struct {
	Host      string                `json:"host"`
	System    string                `json:"system"`
	Purposes  []string              `json:"purposes"`
	Generated []string              `json:"generated"`
	Elements  map[string]outputs    `json:"elements"`
	Graph     map[string]graphEntry `json:"graph"`
}

// outputs maps "home" and "nixos" to the settings an element sets, and "home_imports"
// to the Home Manager modules from flake inputs that those settings need.
type outputs map[string]any

type setting struct {
	Path  []string `json:"path"`
	Value any      `json:"value"`
}

type graphEntry struct {
	Reads    []string `json:"reads"`
	Writes   []string `json:"writes"`
	Requires []string `json:"requires"`
	When     []string `json:"when"`
	Options  []string `json:"options"`
}

func evaluate(host, system, user string, hostFileValues, userFileValues, machineValues starlark.StringDict, elems map[string]*element, purposes []string) (*hostResult, error) {
	g := generated(elems, purposes)
	thread := &starlark.Thread{Name: host, Print: func(*starlark.Thread, string) {}}
	predeclared := builtins()

	globals := map[string]starlark.StringDict{}
	for _, name := range sortedKeys(g) {
		e := elems[name]
		if e.virtual {
			continue
		}
		gl, err := starlark.ExecFileOptions(fileOptions(), thread, e.file, e.src, predeclared)
		if err != nil {
			return nil, err
		}
		globals[name] = gl
	}

	call := func(e *element, fn string, args starlark.Tuple) (starlark.Value, error) {
		f, ok := globals[e.name][fn]
		if !ok {
			return nil, nil
		}
		v, err := starlark.Call(thread, f, args, nil)
		if err != nil {
			return nil, fmt.Errorf("%s: %s: %w", e.file, fn, err)
		}
		if err := rejectRefs(v); err != nil {
			return nil, fmt.Errorf("%s: %s returned %w", e.file, fn, err)
		}
		v.Freeze()
		return v, nil
	}

	// public, in dependency order over the parameters of public.
	hostValues := starlark.StringDict{
		"system": starlark.String(system),
		"linux":  starlark.Bool(strings.HasSuffix(system, "-linux")),
		"darwin": starlark.Bool(strings.HasSuffix(system, "-darwin")),
	}
	for k, v := range hostFileValues {
		if k == "system" && v != starlark.String(system) {
			return nil, fmt.Errorf("host %s: system is %s in its file but %s was requested", host, v, system)
		}
		hostValues[k] = v
	}
	facts := starlarkstruct.FromStringDict(starlarkstruct.Default, hostValues)
	facts.Freeze()
	home := "/home/" + user
	if strings.HasSuffix(system, "-darwin") {
		home = "/Users/" + user
	}
	userValues := starlark.StringDict{
		"name": starlark.String(user),
		"home": starlark.String(home),
	}
	for k, v := range userFileValues {
		userValues[k] = v
	}
	userFacts := starlarkstruct.FromStringDict(starlarkstruct.Default, userValues)
	userFacts.Freeze()
	refs := map[string]*elementRef{
		hostElement: {name: hostElement, public: facts},
		userElement: {name: userElement, public: userFacts},
		machinesElement: {name: machinesElement, public: starlarkstruct.FromStringDict(starlarkstruct.Default, machineValues)},
	}
	refs[machinesElement].public.Freeze()
	var visiting = map[string]bool{}
	var publicOf func(name string) (*elementRef, error)
	publicOf = func(name string) (*elementRef, error) {
		if r, ok := refs[name]; ok {
			return r, nil
		}
		if visiting[name] {
			return nil, fmt.Errorf("%s: public values read each other in a cycle", elems[name].file)
		}
		visiting[name] = true
		e := elems[name]
		var args starlark.Tuple
		if f := e.funcs["public"]; f != nil {
			for _, p := range f.params {
				r, err := publicOf(p)
				if err != nil {
					return nil, err
				}
				args = append(args, r)
			}
		}
		v, err := call(e, "public", args)
		if err != nil {
			return nil, err
		}
		dict := starlark.StringDict{}
		if v != nil {
			d, ok := v.(*starlark.Dict)
			if !ok {
				return nil, fmt.Errorf("%s: public must return a dict", e.file)
			}
			for _, item := range d.Items() {
				k, ok := item[0].(starlark.String)
				if !ok {
					return nil, fmt.Errorf("%s: public keys must be strings", e.file)
				}
				dict[string(k)] = item[1]
			}
		}
		s := starlarkstruct.FromStringDict(starlarkstruct.Default, dict)
		s.Freeze()
		r := &elementRef{name: name, public: s}
		refs[name] = r
		return r, nil
	}
	for _, name := range sortedKeys(g) {
		if _, err := publicOf(name); err != nil {
			return nil, err
		}
	}

	argsFor := func(f *funcInfo, incoming starlark.Value) starlark.Tuple {
		var args starlark.Tuple
		for _, p := range f.params {
			if p == incomingParam {
				args = append(args, incoming)
			} else {
				args = append(args, refs[p])
			}
		}
		return args
	}

	// writes
	in := map[string][]starlark.Value{}
	for _, name := range sortedKeys(g) {
		e := elems[name]
		f := e.funcs["writes"]
		if f == nil {
			continue
		}
		v, err := call(e, "writes", argsFor(f, nil))
		if err != nil {
			return nil, err
		}
		list, ok := v.(*starlark.List)
		if !ok {
			return nil, fmt.Errorf("%s: writes must return a list of write(...)", e.file)
		}
		for i := 0; i < list.Len(); i++ {
			w, ok := list.Index(i).(*writeRecord)
			if !ok {
				return nil, fmt.Errorf("%s: writes must return a list of write(...)", e.file)
			}
			if !f.writes[w.target] {
				return nil, fmt.Errorf("%s: wrote to %q, which is not a write target of writes", e.file, w.target)
			}
			in[w.target] = append(in[w.target], starlarkstruct.FromStringDict(starlarkstruct.Default, starlark.StringDict{
				"source": starlark.String(name), "value": w.value,
			}))
		}
	}

	res := &hostResult{Host: host, System: system, Purposes: purposes, Generated: sortedKeys(g),
		Elements: map[string]outputs{}, Graph: map[string]graphEntry{}}
	for _, name := range sortedKeys(g) {
		e := elems[name]
		if e.virtual {
			continue
		}
		entry := graphEntry{Requires: nonNil(e.requires), When: nonNil(e.when)}
		reads, writes := map[string]bool{}, map[string]bool{}
		for _, f := range e.funcs {
			for p := range f.reads {
				if p != incomingParam {
					reads[p] = true
				}
			}
			for p := range f.writes {
				writes[p] = true
			}
		}
		entry.Reads, entry.Writes = nonNil(sortedKeys(reads)), nonNil(sortedKeys(writes))

		out := outputs{}
		if f := e.funcs["config"]; f != nil {
			incoming := starlark.NewList(in[name]) // already ordered by source name
			incoming.Freeze()
			v, err := call(e, "config", argsFor(f, incoming))
			if err != nil {
				return nil, err
			}
			out, err = configJSON(e, v)
			if err != nil {
				return nil, err
			}
		} else if len(in[name]) > 0 {
			return nil, fmt.Errorf("%s: receives writes but has no config", e.file)
		}
		var options []string
		for _, class := range []string{"home", "nixos"} {
			settings, _ := out[class].([]setting)
			for _, s := range settings {
				options = append(options, class+":"+strings.Join(s.Path, "."))
			}
		}
		entry.Options = nonNil(options)
		res.Elements[name] = out
		res.Graph[name] = entry
	}
	return res, nil
}

func configJSON(e *element, v starlark.Value) (outputs, error) {
	d, ok := v.(*starlark.Dict)
	if !ok {
		return nil, fmt.Errorf("%s: config must return a dict", e.file)
	}
	out := outputs{}
	for _, item := range d.Items() {
		k, ok := item[0].(starlark.String)
		if ok && (k == "home_imports" || k == "nixos_imports") {
			imports, err := moduleList(item[1])
			if err != nil {
				return nil, fmt.Errorf("%s: %s: %w", e.file, k, err)
			}
			out[string(k)] = imports
			continue
		}
		if !ok || (k != "home" && k != "nixos") {
			return nil, fmt.Errorf("%s: config keys must be home, nixos, home_imports or nixos_imports", e.file)
		}
		opts, ok := item[1].(*starlark.Dict)
		if !ok {
			return nil, fmt.Errorf("%s: config[%s] must be a dict of option paths", e.file, k)
		}
		var settings []setting
		for _, o := range opts.Items() {
			path, err := optionPath(o[0])
			if err != nil {
				return nil, fmt.Errorf("%s: %w", e.file, err)
			}
			j, err := toJSON(o[1])
			if err != nil {
				return nil, fmt.Errorf("%s: %s: %w", e.file, strings.Join(path, "."), err)
			}
			settings = append(settings, setting{Path: path, Value: j})
		}
		sort.Slice(settings, func(i, j int) bool {
			return strings.Join(settings[i].Path, "\x00") < strings.Join(settings[j].Path, "\x00")
		})
		out[string(k)] = settings
	}
	return out, nil
}

func moduleList(v starlark.Value) ([]any, error) {
	list, ok := v.(*starlark.List)
	if !ok {
		return nil, fmt.Errorf("must be a list of module(...)")
	}
	out := []any{}
	for i := 0; i < list.Len(); i++ {
		m, ok := list.Index(i).(*marker)
		if !ok {
			return nil, fmt.Errorf("must be a list of module(...) or repoModule(...)")
		}
		j := m.json.(map[string]any)
		_, isModule := j["$module"]
		_, isRepo := j["$repoModule"]
		if !isModule && !isRepo {
			return nil, fmt.Errorf("must be a list of module(...) or repoModule(...)")
		}
		out = append(out, j)
	}
	return out, nil
}

// optionPath accepts "a.b.c", or a tuple of names for paths whose names contain dots
// (("xdg", "dataFile", "nvim/nix/features.lua", "text")).
func optionPath(k starlark.Value) ([]string, error) {
	switch x := k.(type) {
	case starlark.String:
		if x == "" {
			return nil, fmt.Errorf("empty option path")
		}
		return strings.Split(string(x), "."), nil
	case starlark.Tuple:
		var path []string
		for _, p := range x {
			s, ok := p.(starlark.String)
			if !ok || s == "" {
				return nil, fmt.Errorf("option path %s must hold non-empty strings", x)
			}
			path = append(path, string(s))
		}
		if len(path) == 0 {
			return nil, fmt.Errorf("empty option path")
		}
		return path, nil
	}
	return nil, fmt.Errorf("option path must be a string or a tuple of strings, got %s", k.Type())
}

func toJSON(v starlark.Value) (any, error) {
	switch x := v.(type) {
	case starlark.NoneType:
		return nil, nil
	case starlark.Bool:
		return bool(x), nil
	case starlark.Int:
		i, ok := x.Int64()
		if !ok {
			return nil, fmt.Errorf("integer too large")
		}
		return i, nil
	case starlark.Float:
		return float64(x), nil
	case starlark.String:
		if strings.Contains(string(x), markerSentinel) {
			return nil, fmt.Errorf("a pkg/exe/concat value was turned into text; use concat(...) instead of str() or format()")
		}
		return string(x), nil
	case *marker:
		return x.json, nil
	case *starlark.List:
		out := []any{}
		for i := 0; i < x.Len(); i++ {
			j, err := toJSON(x.Index(i))
			if err != nil {
				return nil, err
			}
			out = append(out, j)
		}
		return out, nil
	case starlark.Tuple:
		return toJSON(starlark.NewList(x))
	case *starlark.Dict:
		out := map[string]any{}
		for _, item := range x.Items() {
			k, ok := item[0].(starlark.String)
			if !ok {
				return nil, fmt.Errorf("dict keys must be strings")
			}
			j, err := toJSON(item[1])
			if err != nil {
				return nil, err
			}
			out[string(k)] = j
		}
		return out, nil
	}
	return nil, fmt.Errorf("cannot output a value of type %s", v.Type())
}

// rejectRefs refuses values that carry an element reference, so a parameter cannot be
// handed to another element through public values or written values.
func rejectRefs(v starlark.Value) error {
	switch x := v.(type) {
	case *elementRef:
		return fmt.Errorf("an element reference (%s); pass values, not elements", x.name)
	case *writeRecord:
		return rejectRefs(x.value)
	case *starlark.List:
		for i := 0; i < x.Len(); i++ {
			if err := rejectRefs(x.Index(i)); err != nil {
				return err
			}
		}
	case starlark.Tuple:
		for _, y := range x {
			if err := rejectRefs(y); err != nil {
				return err
			}
		}
	case *starlark.Dict:
		for _, item := range x.Items() {
			if err := rejectRefs(item[0]); err != nil {
				return err
			}
			if err := rejectRefs(item[1]); err != nil {
				return err
			}
		}
	case *starlarkstruct.Struct:
		for _, n := range x.AttrNames() {
			a, _ := x.Attr(n)
			if err := rejectRefs(a); err != nil {
				return err
			}
		}
	case *starlark.Function, *starlark.Builtin:
		return fmt.Errorf("a function; pass values, not functions")
	}
	return nil
}

func nonNil(xs []string) []string {
	if xs == nil {
		return []string{}
	}
	sort.Strings(xs)
	return xs
}
