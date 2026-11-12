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

// reason records why an element is true for a user: an axiom, or the rule that derived it.
type reason struct {
	Axiom string   `json:"axiom,omitempty"` // "machine" or "purposes"
	Rule  string   `json:"rule,omitempty"`  // "requires", "parameter" or "when"
	From  []string `json:"from,omitempty"`  // the antecedents of the rule
}

// derive computes the least set of elements closed under the rules (a reference from a true
// element, or a when whose elements are all true), starting from the axioms. Each element
// keeps the first reason found, in a fixed order, so the reasons are deterministic.
func derive(elems map[string]*element, axioms map[string]string) map[string]reason {
	g := map[string]reason{}
	for name, kind := range axioms {
		g[name] = reason{Axiom: kind}
	}
	for changed := true; changed; {
		changed = false
		for _, e := range sortedElems(elems) {
			if _, ok := g[e.name]; ok {
				for _, r := range e.refs() {
					if _, ok := g[r]; !ok {
						rule := "parameter"
						for _, q := range e.requires {
							if q == r {
								rule = "requires"
							}
						}
						g[r] = reason{Rule: rule, From: []string{e.name}}
						changed = true
					}
				}
				continue
			}
			if e.derived() && allIn(e.when, g) {
				g[e.name] = reason{Rule: "when", From: e.when}
				changed = true
			}
		}
	}
	return g
}

func allIn[V any](xs []string, set map[string]V) bool {
	for _, x := range xs {
		if _, ok := set[x]; !ok {
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
		"activation":     activation, "inputPkg": inputPkg, "file": file,
		"shellApp": generic("shellApp", 3), "shellAppEnv": generic("shellAppEnv", 4),
		"repoPkg": generic("repoPkg", 1), "repoText": generic("repoText", 1),
		"symlinkJoin": generic("symlinkJoin", 2), "symlinkJoinBuild": generic("symlinkJoinBuild", 4),
		"toJSON": generic("toJSON", 1), "pkgSetFn": generic("pkgSetFn", 1),
		"pkgWithPackages": generic("pkgWithPackages", 2),
		"mkAfter":         generic("mkAfter", 1), "mkBefore": generic("mkBefore", 1),
		"flakeRev": generic("flakeRev", 0), "repoPkgWith": generic("repoPkgWith", 2),
		"repoPath": generic("repoPath", 1), "pythonWithModules": generic("pythonWithModules", 1), "command": generic("command", 2),
		"gvariantTuple": generic("gvariantTuple", 1),
		"struct":        starlark.NewBuiltin("struct", starlarkstruct.Make),
	}
}

type hostResult struct {
	Host      string                 `json:"host"`
	System    string                 `json:"system"`
	Machine   string                 `json:"machine"`
	Generated []string               `json:"generated"`
	Elements  map[string]outputs     `json:"elements"`
	Users     map[string]*userResult `json:"users"`
	Graph     map[string]graphEntry  `json:"graph"`
}

// userResult is what one user gets: the elements true for the user, why each is true, and
// the per-user settings other than NixOS ones (those go to hostResult.Elements, because
// NixOS has one configuration for all users).
type userResult struct {
	Purposes  []string           `json:"purposes"`
	Generated []string           `json:"generated"`
	Reasons   map[string]reason  `json:"reasons"`
	Elements  map[string]outputs `json:"elements"`
}

// outputs maps "home" and "nixos" to the settings an element sets, and "home_imports"
// and "nixos_imports" to the modules that those settings need.
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

type writeEntry struct {
	source string
	target string
	value  starlark.Value
}

// levels tells which functions see per-user values. The public values of user, and of an
// element whose public reads a per-user value, differ per user. A function that reads one
// of them is evaluated per user; config may not, because the NixOS settings of the host are
// the same whichever user's judgment brought the element in (rule B).
type levels struct {
	elems  map[string]*element
	public map[string]bool
}

func (l *levels) publicPerUser(name string) bool {
	if v, ok := l.public[name]; ok {
		return v
	}
	l.public[name] = false // a cycle is reported when public values are evaluated
	e := l.elems[name]
	v := name == userElement
	if f := e.funcs["public"]; f != nil {
		v = l.readsPerUser(f)
	}
	l.public[name] = v
	return v
}

func (l *levels) readsPerUser(f *funcInfo) bool {
	for _, p := range f.params {
		if p != incomingParam && f.reads[p] && l.publicPerUser(p) {
			return true
		}
	}
	return false
}

func evaluateHost(host, system string, spec *hostSpec, userFiles map[string]starlark.StringDict, machineValues starlark.StringDict, elems map[string]*element) (*hostResult, error) {
	judgments := map[string]map[string]reason{}
	all := map[string]bool{}
	for _, u := range spec.users {
		axioms := map[string]string{}
		if spec.machine != "" {
			axioms[spec.machine] = "machine"
		}
		for _, p := range u.purposes {
			axioms[p] = "purposes"
		}
		judgments[u.name] = derive(elems, axioms)
		for n := range judgments[u.name] {
			all[n] = true
		}
	}

	thread := &starlark.Thread{Name: host, Print: func(*starlark.Thread, string) {}}
	predeclared := builtins()
	globals := map[string]starlark.StringDict{}
	for _, name := range sortedKeys(all) {
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

	lv := &levels{elems: elems, public: map[string]bool{}}
	for _, name := range sortedKeys(all) {
		e := elems[name]
		if f := e.funcs["config"]; f != nil && lv.readsPerUser(f) {
			return nil, fmt.Errorf("%s: config reads a value that differs per user (user, or an element whose public reads it); move the per-user part to user_config", e.file)
		}
	}

	hostValues := starlark.StringDict{
		"system": starlark.String(system),
		"linux":  starlark.Bool(strings.HasSuffix(system, "-linux")),
		"darwin": starlark.Bool(strings.HasSuffix(system, "-darwin")),
	}
	for k, v := range spec.values {
		if k == "system" && v != starlark.String(system) {
			return nil, fmt.Errorf("host %s: system is %s in its file but %s was requested", host, v, system)
		}
		hostValues[k] = v
	}
	facts := starlarkstruct.FromStringDict(starlarkstruct.Default, hostValues)
	facts.Freeze()
	machines := starlarkstruct.FromStringDict(starlarkstruct.Default, machineValues)
	machines.Freeze()
	hostRefs := map[string]*elementRef{
		hostElement:     {name: hostElement, public: facts},
		machinesElement: {name: machinesElement, public: machines},
	}

	publicOfIn := func(refs map[string]*elementRef) func(string) (*elementRef, error) {
		visiting := map[string]bool{}
		var publicOf func(string) (*elementRef, error)
		publicOf = func(name string) (*elementRef, error) {
			if r, ok := refs[name]; ok {
				return r, nil
			}
			e := elems[name]
			if e.virtual {
				return nil, fmt.Errorf("%s is only available to functions evaluated per user", name)
			}
			if visiting[name] {
				return nil, fmt.Errorf("%s: public values read each other in a cycle", e.file)
			}
			visiting[name] = true
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
		return publicOf
	}

	argsFor := func(f *funcInfo, refs map[string]*elementRef, incoming starlark.Value) starlark.Tuple {
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

	runWrites := func(e *element, refs map[string]*elementRef) ([]writeEntry, error) {
		f := e.funcs["writes"]
		v, err := call(e, "writes", argsFor(f, refs, nil))
		if err != nil {
			return nil, err
		}
		list, ok := v.(*starlark.List)
		if !ok {
			return nil, fmt.Errorf("%s: writes must return a list of write(...)", e.file)
		}
		var out []writeEntry
		for i := 0; i < list.Len(); i++ {
			w, ok := list.Index(i).(*writeRecord)
			if !ok {
				return nil, fmt.Errorf("%s: writes must return a list of write(...)", e.file)
			}
			if !f.writes[w.target] {
				return nil, fmt.Errorf("%s: wrote to %q, which is not a write target of writes", e.file, w.target)
			}
			out = append(out, writeEntry{source: e.name, target: w.target, value: w.value})
		}
		return out, nil
	}

	incomingList := func(entries []writeEntry) *starlark.List {
		sort.SliceStable(entries, func(i, j int) bool { return entries[i].source < entries[j].source })
		var items []starlark.Value
		for _, w := range entries {
			items = append(items, starlarkstruct.FromStringDict(starlarkstruct.Default, starlark.StringDict{
				"source": starlark.String(w.source), "value": w.value,
			}))
		}
		l := starlark.NewList(items)
		l.Freeze()
		return l
	}

	countOut := func(out outputs) int {
		n := 0
		for _, v := range out {
			switch x := v.(type) {
			case []setting:
				n += len(x)
			case []any:
				n += len(x)
			}
		}
		return n
	}

	// Host context: public values that are the same for every user, the writes that read
	// only those, and config.
	hostPublic := publicOfIn(hostRefs)
	for _, name := range sortedKeys(all) {
		if !elems[name].virtual && !lv.publicPerUser(name) {
			if _, err := hostPublic(name); err != nil {
				return nil, err
			}
		}
	}
	var hostWrites []writeEntry
	hostWritesBy := map[string]int{}
	for _, name := range sortedKeys(all) {
		e := elems[name]
		if f := e.funcs["writes"]; f != nil && !lv.readsPerUser(f) {
			ws, err := runWrites(e, hostRefs)
			if err != nil {
				return nil, err
			}
			hostWrites = append(hostWrites, ws...)
			hostWritesBy[name] = len(ws)
		}
	}
	writesTo := func(entries []writeEntry, target string, from map[string]reason) []writeEntry {
		var out []writeEntry
		for _, w := range entries {
			if _, ok := from[w.source]; w.target == target && (from == nil || ok) {
				out = append(out, w)
			}
		}
		return out
	}

	res := &hostResult{Host: host, System: system, Machine: spec.machine, Generated: sortedKeys(all),
		Elements: map[string]outputs{}, Users: map[string]*userResult{}, Graph: map[string]graphEntry{}}
	options := map[string]map[string]bool{}
	addOptions := func(name string, out outputs) {
		if options[name] == nil {
			options[name] = map[string]bool{}
		}
		for _, class := range []string{"home", "nixos"} {
			settings, _ := out[class].([]setting)
			for _, s := range settings {
				options[name][class+":"+strings.Join(s.Path, ".")] = true
			}
		}
	}
	for _, name := range sortedKeys(all) {
		e := elems[name]
		if e.virtual {
			continue
		}
		incoming := writesTo(hostWrites, name, nil)
		out := outputs{}
		if f := e.funcs["config"]; f != nil {
			v, err := call(e, "config", argsFor(f, hostRefs, incomingList(incoming)))
			if err != nil {
				return nil, err
			}
			out, err = configJSON(e, "config", v, []string{"nixos", "nixos_imports"})
			if err != nil {
				return nil, err
			}
		} else if len(incoming) > 0 && e.funcs["user_config"] == nil {
			return nil, fmt.Errorf("%s: receives writes but has neither config nor user_config", e.file)
		}
		hostWriter := e.funcs["writes"] != nil && !lv.readsPerUser(e.funcs["writes"])
		if (e.funcs["config"] != nil || hostWriter) && countOut(out)+hostWritesBy[name] == 0 {
			return nil, fmt.Errorf("%s: produced no settings and no writes on host %s; an element that enters the machine must add something (rule A). Put the condition in requires or when instead of returning nothing", e.file, host)
		}
		res.Elements[name] = out
		addOptions(name, out)
	}

	// User context, per user: per-user public values and writes, and user_config.
	for _, u := range spec.users {
		g := judgments[u.name]
		home := "/home/" + u.name
		if strings.HasSuffix(system, "-darwin") {
			home = "/Users/" + u.name
		}
		userValues := starlark.StringDict{"name": starlark.String(u.name), "home": starlark.String(home)}
		for k, v := range userFiles[u.name] {
			userValues[k] = v
		}
		for k, v := range u.values {
			if _, dup := userFiles[u.name][k]; dup {
				return nil, fmt.Errorf("host %s: user %s sets %s both in the host file and in config/users/%s.toml", host, u.name, k, u.name)
			}
			if k == "home" {
				return nil, fmt.Errorf("host %s: user %s: home is set by confgen", host, u.name)
			}
			userValues[k] = v
		}
		userFacts := starlarkstruct.FromStringDict(starlarkstruct.Default, userValues)
		userFacts.Freeze()
		refs := map[string]*elementRef{userElement: {name: userElement, public: userFacts}}
		for k, v := range hostRefs {
			refs[k] = v
		}
		userPublic := publicOfIn(refs)
		for _, name := range sortedKeys(g) {
			if _, err := userPublic(name); err != nil {
				return nil, err
			}
		}
		var userWrites []writeEntry
		userWritesBy := map[string]int{}
		for _, name := range sortedKeys(g) {
			e := elems[name]
			if f := e.funcs["writes"]; f != nil && lv.readsPerUser(f) {
				ws, err := runWrites(e, refs)
				if err != nil {
					return nil, err
				}
				userWrites = append(userWrites, ws...)
				userWritesBy[name] = len(ws)
			}
		}
		ur := &userResult{Purposes: nonNil(append([]string{}, u.purposes...)), Generated: sortedKeys(g), Reasons: g, Elements: map[string]outputs{}}
		for _, name := range sortedKeys(g) {
			e := elems[name]
			if e.virtual {
				continue
			}
			mine := writesTo(userWrites, name, nil)
			out := outputs{}
			if f := e.funcs["user_config"]; f != nil {
				incoming := append(writesTo(hostWrites, name, g), mine...)
				v, err := call(e, "user_config", argsFor(f, refs, incomingList(incoming)))
				if err != nil {
					return nil, err
				}
				out, err = configJSON(e, "user_config", v, []string{"home", "home_imports", "nixos"})
				if err != nil {
					return nil, err
				}
			} else if len(mine) > 0 {
				return nil, fmt.Errorf("%s: receives writes that differ per user but has no user_config", e.file)
			}
			userWriter := e.funcs["writes"] != nil && lv.readsPerUser(e.funcs["writes"])
			if (e.funcs["user_config"] != nil || userWriter) && countOut(out)+userWritesBy[name] == 0 {
				return nil, fmt.Errorf("%s: produced no settings and no writes for user %s on host %s; an element that is true for a user must add something for the user (rule A). Put the condition in requires or when, or let the user leave the purpose out, instead of returning nothing", e.file, u.name, host)
			}
			addOptions(name, out)
			if nixos, ok := out["nixos"].([]setting); ok {
				hostOut := res.Elements[name]
				prev, _ := hostOut["nixos"].([]setting)
				hostOut["nixos"] = append(prev, nixos...)
				delete(out, "nixos")
			}
			ur.Elements[name] = out
		}
		res.Users[u.name] = ur
	}

	for _, name := range sortedKeys(all) {
		e := elems[name]
		if e.virtual {
			continue
		}
		entry := graphEntry{Requires: nonNil(e.requires), When: nonNil(e.when), Options: nonNil(sortedKeys(options[name]))}
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
		res.Graph[name] = entry
	}
	return res, nil
}

func configJSON(e *element, fn string, v starlark.Value, allowed []string) (outputs, error) {
	d, ok := v.(*starlark.Dict)
	if !ok {
		return nil, fmt.Errorf("%s: %s must return a dict", e.file, fn)
	}
	allow := map[string]bool{}
	for _, k := range allowed {
		allow[k] = true
	}
	out := outputs{}
	for _, item := range d.Items() {
		k, ok := item[0].(starlark.String)
		if !ok || !allow[string(k)] {
			return nil, fmt.Errorf("%s: %s keys must be %s", e.file, fn, strings.Join(allowed, ", "))
		}
		if k == "home_imports" || k == "nixos_imports" {
			imports, err := moduleList(item[1])
			if err != nil {
				return nil, fmt.Errorf("%s: %s: %w", e.file, k, err)
			}
			out[string(k)] = imports
			continue
		}
		opts, ok := item[1].(*starlark.Dict)
		if !ok {
			return nil, fmt.Errorf("%s: %s[%s] must be a dict of option paths", e.file, fn, k)
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
