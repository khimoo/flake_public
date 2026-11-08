package main

import (
	"fmt"
	"path/filepath"
	"strings"

	"go.starlark.net/starlark"
)

// alone selects each element as a host's only purpose and reports the elements whose
// generation then fails. It reuses the values of a host that already generates the
// element, so a failure means the element relied on another element that this host
// happened to select. Elements no host generates are reported too, since they were
// never checked.
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
		purposes, hostValues, err := loadHost(file, elems)
		if err != nil {
			continue
		}
		system := "x86_64-linux"
		if s, ok := hostValues["system"].(starlark.String); ok {
			system = string(s)
		}
		user := firstUser(hostValues)
		userValues, err := loadUserFile(filepath.Join(dir, "users", user+".toml"))
		if err != nil {
			return nil, err
		}
		r, err := evaluate(host, system, user, hostValues, userValues, machines, elems, purposes)
		if err != nil {
			// Hosts under tests/ that exist to be rejected land here.
			continue
		}
		for _, name := range r.Generated {
			e := elems[name]
			if checked[name] || e.virtual || e.derived() {
				continue
			}
			checked[name] = true
			if _, err := evaluate(host, system, user, hostValues, userValues, machines, elems, []string{name}); err != nil {
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

// firstUser picks the user that tests/default.nix also builds a rejected host for. One
// user is enough here: what differs between users is values, not which elements exist.
func firstUser(hostValues starlark.StringDict) string {
	users, ok := hostValues["users"].(*starlark.List)
	if !ok || users.Len() == 0 {
		return "test"
	}
	d, ok := users.Index(0).(*starlark.Dict)
	if !ok {
		return "test"
	}
	v, found, _ := d.Get(starlark.String("name"))
	if s, ok := v.(starlark.String); found && ok {
		return string(s)
	}
	return "test"
}
