// confgen evaluates the Starlark elements under config/ and writes one JSON file per
// host for lib/confgen.nix. Design: docs/architecture/confgen.md.
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
  confgen build <config-dir> <out-dir>
  confgen explain <config-dir> <host> <element>`

func run(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("%s", usage)
	}
	switch {
	case args[0] == "build" && len(args) == 3:
		results, err := buildAll(args[1])
		if err != nil {
			return err
		}
		if err := os.MkdirAll(args[2], 0o755); err != nil {
			return err
		}
		for _, r := range results {
			data, err := json.MarshalIndent(r, "", "  ")
			if err != nil {
				return err
			}
			if err := os.WriteFile(filepath.Join(args[2], r.Host+".json"), append(data, '\n'), 0o644); err != nil {
				return err
			}
		}
		return nil
	case args[0] == "explain" && len(args) == 4:
		return explain(args[1], args[2], args[3])
	}
	return fmt.Errorf("%s", usage)
}

func buildAll(dir string) ([]*hostResult, error) {
	elems, err := loadElements(filepath.Join(dir, "elements"))
	if err != nil {
		return nil, err
	}
	hosts, err := filepath.Glob(filepath.Join(dir, "hosts", "*.star"))
	if err != nil {
		return nil, err
	}
	var results []*hostResult
	for _, h := range hosts {
		purposes, err := loadHost(h, elems)
		if err != nil {
			return nil, err
		}
		r, err := evaluate(strings.TrimSuffix(filepath.Base(h), ".star"), elems, purposes)
		if err != nil {
			return nil, err
		}
		results = append(results, r)
	}
	return results, nil
}

// explain prints what a change to one element can affect on one host.
func explain(dir, host, name string) error {
	results, err := buildAll(dir)
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
	var r *hostResult
	for _, x := range results {
		if x.Host == host {
			r = x
		}
	}
	if r == nil {
		return fmt.Errorf("unknown host %q", host)
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
