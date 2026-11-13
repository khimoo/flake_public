// confgen evaluates the Starlark elements under config/ for one host and writes the
// JSON that modules/nixos/confgen.nix and modules/home-manager/confgen.nix read. Design: docs/architecture/confgen.md.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"go.starlark.net/starlark"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "confgen:", err)
		os.Exit(1)
	}
}

const usage = `usage:
  confgen build <config-dir> <host> <system> <out.json>
  confgen explain <config-dir> <host> <system> <element>
  confgen why <config-dir> <host> <system> <user> <element>   (prints the axiom and rules that make element true for user)
  confgen affected <repo-root> <changed-path>...   (prints {"elements": [...], "hosts": [...]}; elements is ["ALL"] when every check must run)
  confgen alone <config-dir>   (fails if an element cannot be generated as a user's only purpose)`

func run(args []string) error {
	if len(args) >= 2 && args[0] == "affected" {
		names, err := affected(args[1], args[2:])
		if err != nil {
			return err
		}
		hosts, err := affectedHosts(args[1], names)
		if err != nil {
			return err
		}
		data, err := json.Marshal(map[string][]string{"elements": nonNil(names), "hosts": nonNil(hosts)})
		if err != nil {
			return err
		}
		fmt.Println(string(data))
		return nil
	}
	if len(args) == 2 && args[0] == "alone" {
		failures, err := alone(args[1])
		if err != nil {
			return err
		}
		for _, f := range failures {
			fmt.Println(f)
		}
		if len(failures) > 0 {
			return fmt.Errorf("%d elements cannot be generated alone", len(failures))
		}
		return nil
	}
	switch {
	case len(args) == 5 && args[0] == "build":
		r, err := buildHost(args[1], args[2], args[3])
		if err != nil {
			return err
		}
		data, err := json.MarshalIndent(r, "", "  ")
		if err != nil {
			return err
		}
		return os.WriteFile(args[4], append(data, '\n'), 0o644)
	case len(args) == 5 && args[0] == "explain":
		return explain(args[1], args[2], args[3], args[4])
	case len(args) == 6 && args[0] == "why":
		return why(args[1], args[2], args[3], args[4], args[5])
	}
	return fmt.Errorf("%s", usage)
}

func buildHost(dir, host, system string) (*hostResult, error) {
	elems, err := loadElements(filepath.Join(dir, "elements"))
	if err != nil {
		return nil, err
	}
	spec, err := loadHost(filepath.Join(dir, "hosts", host+".toml"), elems)
	if err != nil {
		return nil, err
	}
	userFiles, err := loadUserFiles(dir, spec)
	if err != nil {
		return nil, err
	}
	machines, err := loadMachines(filepath.Join(dir, "hosts"))
	if err != nil {
		return nil, err
	}
	return evaluateHost(host, system, spec, userFiles, machines, elems)
}

func loadUserFiles(dir string, spec *hostSpec) (map[string]starlark.StringDict, error) {
	out := map[string]starlark.StringDict{}
	for _, u := range spec.users {
		v, err := loadUserFile(filepath.Join(dir, "users", u.name+".toml"))
		if err != nil {
			return nil, err
		}
		out[u.name] = v
	}
	return out, nil
}

// why prints the chain of rules that makes an element true for a user, down to the axioms.
func why(dir, host, system, user, name string) error {
	r, err := buildHost(dir, host, system)
	if err != nil {
		return err
	}
	u, ok := r.Users[user]
	if !ok {
		return fmt.Errorf("host %s has no user %q", host, user)
	}
	if _, ok := u.Reasons[name]; !ok {
		fmt.Printf("%s is not true for %s on %s\n", name, user, host)
		return nil
	}
	var show func(n, indent string)
	show = func(n, indent string) {
		rs := u.Reasons[n]
		switch {
		case rs.Axiom != "":
			fmt.Printf("%s%s  (axiom: %s)\n", indent, n, rs.Axiom)
		case rs.Rule == "when":
			fmt.Printf("%s%s  (when %s)\n", indent, n, strings.Join(rs.From, ", "))
			for _, f := range rs.From {
				show(f, indent+"  ")
			}
		default:
			fmt.Printf("%s%s  (%s of %s)\n", indent, n, rs.Rule, rs.From[0])
			show(rs.From[0], indent+"  ")
		}
	}
	show(name, "")
	return nil
}

// explain prints what a change to one element can affect on one host.
func explain(dir, host, system, name string) error {
	r, err := buildHost(dir, host, system)
	if err != nil {
		return err
	}
	elems, err := loadElements(filepath.Join(dir, "elements"))
	if err != nil {
		return err
	}
	e, ok := elems[name]
	if !ok {
		return fmt.Errorf("unknown element %q", name)
	}
	var readBy, writtenBy, conditionOf, requiredBy, neededBy []string
	for _, other := range sortedElems(elems) {
		for _, f := range other.funcs {
			if f.reads[name] {
				readBy = append(readBy, other.name)
			}
			if f.writes[name] {
				writtenBy = append(writtenBy, other.name)
			}
		}
		for _, w := range other.when {
			if w == name {
				conditionOf = append(conditionOf, other.name)
			}
		}
		for _, q := range other.requires {
			if q == name {
				requiredBy = append(requiredBy, other.name)
			}
		}
		for _, q := range other.needs {
			if q == name {
				neededBy = append(neededBy, other.name)
			}
		}
	}
	generated := false
	for _, g := range r.Generated {
		generated = generated || g == name
	}
	fmt.Printf("%s (%s)\n", name, e.file)
	fmt.Printf("  generated on %s: %v\n", host, generated)
	fmt.Printf("  read by:        %s\n", strings.Join(uniq(readBy), ", "))
	fmt.Printf("  written by:     %s\n", strings.Join(uniq(writtenBy), ", "))
	fmt.Printf("  required by:    %s\n", strings.Join(requiredBy, ", "))
	fmt.Printf("  condition of:   %s\n", strings.Join(conditionOf, ", "))
	fmt.Printf("  needed by:      %s\n", strings.Join(neededBy, ", "))
	fmt.Printf("  needs:          %s\n", strings.Join(e.needs, ", "))
	if g, ok := r.Graph[name]; ok {
		fmt.Printf("  writes to:      %s\n", strings.Join(g.Writes, ", "))
		fmt.Printf("  sets options:   %s\n", strings.Join(g.Options, ", "))
	}
	return nil
}
