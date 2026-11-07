// confgen evaluates the Starlark elements under config/ for one host and writes the
// JSON that modules/home-manager/confgen.nix reads. Design: docs/architecture/confgen.md.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "confgen:", err)
		os.Exit(1)
	}
}

const usage = `usage:
  confgen build <config-dir> <host> <system> <out.json>
  confgen explain <config-dir> <host> <system> <element>`

func run(args []string) error {
	if len(args) != 5 {
		return fmt.Errorf("%s", usage)
	}
	dir, host, system := args[1], args[2], args[3]
	switch args[0] {
	case "build":
		r, err := buildHost(dir, host, system)
		if err != nil {
			return err
		}
		data, err := json.MarshalIndent(r, "", "  ")
		if err != nil {
			return err
		}
		return os.WriteFile(args[4], append(data, '\n'), 0o644)
	case "explain":
		return explain(dir, host, system, args[4])
	}
	return fmt.Errorf("%s", usage)
}

func buildHost(dir, host, system string) (*hostResult, error) {
	elems, err := loadElements(filepath.Join(dir, "elements"))
	if err != nil {
		return nil, err
	}
	purposes, err := loadHost(filepath.Join(dir, "hosts", host+".star"), elems)
	if err != nil {
		return nil, err
	}
	return evaluate(host, system, elems, purposes)
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
	var readBy, writtenBy, conditionOf, requiredBy []string
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
	if g, ok := r.Graph[name]; ok {
		fmt.Printf("  writes to:      %s\n", strings.Join(g.Writes, ", "))
		fmt.Printf("  sets options:   %s\n", strings.Join(g.Options, ", "))
	}
	return nil
}
