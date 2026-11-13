package main

import (
	"fmt"
	"path/filepath"
	"strings"

	"go.starlark.net/starlark"
)

// alone selects each element as the only purpose of a host's first user, keeping the host's
// machine element, and reports the elements whose generation then fails. It reuses the values
// of a host that already generates the element, so a failure means the element relied on
// another element that this host's users happened to select. Elements no host generates are
// reported too, since they were never checked.
func alone(dir string) ([]string, error) {
	elems, err := loadElements(filepath.Join(dir, "elements"))
	if err != nil {
		return nil, err
	}
	machines, err := loadMachines(filepath.Join(dir, "hosts"))
	if err != nil {
		return nil, err
	}
	files, err := filepath.Glob(filepath.Join(dir, "hosts", "*.toml"))
	if err != nil {
		return nil, err
	}
	checked := map[string]bool{}
	var failures []string
	for _, file := range files {
		host := strings.TrimSuffix(filepath.Base(file), ".toml")
		spec, err := loadHost(file, elems)
		if err != nil {
			continue
		}
		system := "x86_64-linux"
		if s, ok := spec.values["system"].(starlark.String); ok {
			system = string(s)
		}
		userFiles, err := loadUserFiles(dir, spec)
		if err != nil {
			return nil, err
		}
		r, err := evaluateHost(host, system, spec, userFiles, machines, elems)
		if err != nil {
			// Hosts under tests/ that exist to be rejected land here.
			continue
		}
		for _, name := range r.Generated {
			e := elems[name]
			if checked[name] || e.virtual || e.derived() {
				continue
			}
			if e.declaresMachine() {
				// Machine elements, facts and roles come from the machine key, not from purposes.
				checked[name] = true
				continue
			}
			checked[name] = true
			first := spec.users[0]
			first.purposes = []string{name}
			single := &hostSpec{machine: spec.machine, users: []userSpec{first}, values: spec.values}
			if _, err := evaluateHost(host, system, single, userFiles, machines, elems); err != nil {
				failures = append(failures, fmt.Sprintf("%s alone (values of host %s): %v", name, host, err))
			}
		}
	}
	for _, e := range sortedElems(elems) {
		if !checked[e.name] && !e.virtual && !e.derived() {
			failures = append(failures, fmt.Sprintf("%s: no host generates it, so it was not checked alone", e.name))
		}
	}
	return failures, nil
}
