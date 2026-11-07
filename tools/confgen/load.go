package main

import (
	"fmt"
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
	funcs    map[string]*funcInfo
}

func (e *element) derived() bool { return len(e.when) > 0 }

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
	hostElement = "host"
	userElement = "user"
)

var elementFuncs = map[string]bool{"public": true, "writes": true, "config": true}
var elementLists = map[string]bool{"requires": true, "when": true}
var identRe = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)

func predeclaredNames() map[string]bool {
	return map[string]bool{"pkg": true, "exe": true, "concat": true, "write": true, "struct": true,
		"luaPackages": true, "checkoutLink": true, "lua": true, "module": true,
		"repoModule": true, "script": true, "scriptBin": true, "activation": true,
		"inputPkg": true, "file": true, "shellApp": true, "repoPkg": true, "symlinkJoin": true,
		"command": true, "gvariantTuple": true, "outOfStoreLink": true}
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
	for _, n := range []string{hostElement, userElement} {
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
				return nil, fmt.Errorf("%s: top-level def %q is not allowed (use public, writes, config or a name starting with _)", s.Def, n)
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
				if id.Name == "requires" {
					e.requires = list
				} else {
					e.when = list
				}
			case strings.HasPrefix(id.Name, "_"):
			default:
				return nil, fmt.Errorf("%s: top-level name %q is not allowed (use requires, when or a name starting with _)", id.NamePos, id.Name)
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
		if id.Name == incomingParam && d.Name.Name != "config" {
			return nil, fmt.Errorf("%s: only config may take %s", id.NamePos, incomingParam)
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
		}
		for _, w := range e.when {
			if _, ok := elems[w]; !ok {
				return fmt.Errorf("%s: unknown element %q in when", e.file, w)
			}
		}
	}
	return nil
}

// loadHost reads config/hosts/<host>.star: `purposes = [...]` (string literals) and other
// `name = value` lines that become host facts (host.<name>), such as device names.
func loadHost(file string, elems map[string]*element) ([]string, starlark.StringDict, error) {
	src, err := os.ReadFile(file)
	if err != nil {
		return nil, nil, err
	}
	f, err := fileOptions().Parse(file, src, 0)
	if err != nil {
		return nil, nil, err
	}
	var list []string
	found := false
	for _, stmt := range f.Stmts {
		s, ok := stmt.(*syntax.AssignStmt)
		if !ok || s.Op != syntax.EQ {
			start, _ := stmt.Span()
			return nil, nil, fmt.Errorf("%s: a host file holds only `name = value` lines", start)
		}
		id, ok := s.LHS.(*syntax.Ident)
		if !ok {
			return nil, nil, fmt.Errorf("%s: a host file holds only `name = value` lines", s.OpPos)
		}
		switch id.Name {
		case "purposes":
			if list, ok = directStrings(s.RHS); !ok {
				return nil, nil, fmt.Errorf("%s: purposes must be a list of string literals", s.OpPos)
			}
			found = true
		case "system", "linux", "darwin":
			return nil, nil, fmt.Errorf("%s: %s is set by confgen", s.OpPos, id.Name)
		}
	}
	if !found {
		return nil, nil, fmt.Errorf("%s: purposes is missing", file)
	}
	for _, p := range list {
		e, ok := elems[p]
		if !ok {
			return nil, nil, fmt.Errorf("%s: unknown element %q", file, p)
		}
		if e.derived() {
			return nil, nil, fmt.Errorf("%s: derived element %q cannot be selected", file, p)
		}
	}
	values, err := starlark.ExecFileOptions(fileOptions(), &starlark.Thread{Name: file}, file, src, nil)
	if err != nil {
		return nil, nil, err
	}
	delete(values, "purposes")
	values.Freeze()
	return list, values, nil
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

// loadUserFile reads config/users/<user>.star: top-level `name = literal` lines that
// become attributes of the user facts element (user.<name>). A missing file is empty.
func loadUserFile(file string) (starlark.StringDict, error) {
	src, err := os.ReadFile(file)
	if os.IsNotExist(err) {
		return starlark.StringDict{}, nil
	}
	if err != nil {
		return nil, err
	}
	f, err := fileOptions().Parse(file, src, 0)
	if err != nil {
		return nil, err
	}
	for _, stmt := range f.Stmts {
		s, ok := stmt.(*syntax.AssignStmt)
		if !ok || s.Op != syntax.EQ {
			start, _ := stmt.Span()
			return nil, fmt.Errorf("%s: a user file holds only `name = value`", start)
		}
		if id, ok := s.LHS.(*syntax.Ident); !ok || id.Name == "name" || id.Name == "home" {
			return nil, fmt.Errorf("%s: name and home are set by confgen", s.OpPos)
		}
	}
	thread := &starlark.Thread{Name: file}
	values, err := starlark.ExecFileOptions(fileOptions(), thread, file, src, nil)
	if err != nil {
		return nil, err
	}
	values.Freeze()
	return values, nil
}
