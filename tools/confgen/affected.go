package main

import (
	"path/filepath"
	"regexp"
	"strings"
)

// allElements stands for "every check": a changed file whose effect on elements confgen
// cannot see (the rules, the bridge, the flake inputs, an unreferenced repo file).
const allElements = "ALL"

var repoPathRe = regexp.MustCompile(`"([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+)"`)

// affected maps changed repo paths to the elements whose tests must run: each changed element,
// the elements that read it, the elements it writes into, and the derived elements it conditions.
// The tests of other elements cannot change, because an element's output depends only on what it
// reads and what is written into it (rule B in docs/architecture/rules.md).
func affected(root string, paths []string) ([]string, error) {
	elems, err := loadElements(filepath.Join(root, "config", "elements"))
	if err != nil {
		return nil, err
	}
	seeds := map[string]bool{}
	for _, p := range paths {
		p = filepath.ToSlash(filepath.Clean(p))
		switch {
		case strings.HasPrefix(p, "docs/"), strings.HasSuffix(p, ".md") && !strings.HasPrefix(p, "config/"):
		case strings.HasPrefix(p, "config/elements/") && strings.HasSuffix(p, ".star"):
			seeds[strings.TrimSuffix(filepath.Base(p), ".star")] = true
		case strings.HasPrefix(p, "config/hosts/"):
			seeds[hostElement] = true
			seeds[machinesElement] = true
			seeds[userElement] = true
		case strings.HasPrefix(p, "config/users/"):
			seeds[userElement] = true
		default:
			users := elementsUsingPath(elems, p)
			if len(users) == 0 {
				return []string{allElements}, nil
			}
			for _, u := range users {
				seeds[u] = true
			}
		}
	}
	out := map[string]bool{}
	for s := range seeds {
		out[s] = true
		if e, ok := elems[s]; ok {
			for _, f := range e.funcs {
				for w := range f.writes {
					out[w] = true
				}
			}
		}
		for _, other := range elems {
			for _, f := range other.funcs {
				if f.reads[s] {
					out[other.name] = true
				}
			}
			for _, w := range other.when {
				if w == s {
					out[other.name] = true
				}
			}
		}
	}
	return sortedKeys(out), nil
}

// elementsUsingPath finds the elements that name a repo path (repoPkg, repoPath, repoText,
// repoModule) equal to p or to a directory containing p.
func elementsUsingPath(elems map[string]*element, p string) []string {
	var found []string
	for _, e := range sortedElems(elems) {
		for _, m := range repoPathRe.FindAllStringSubmatch(string(e.src), -1) {
			if p == m[1] || strings.HasPrefix(p, m[1]+"/") {
				found = append(found, e.name)
				break
			}
		}
	}
	return found
}

// affectedHosts lists the hosts where one of names is true for some user. Only these hosts can evaluate differently.
func affectedHosts(root string, names []string) ([]string, error) {
	dir := filepath.Join(root, "config")
	elems, err := loadElements(filepath.Join(dir, "elements"))
	if err != nil {
		return nil, err
	}
	files, err := filepath.Glob(filepath.Join(dir, "hosts", "*.toml"))
	if err != nil {
		return nil, err
	}
	var hosts []string
	for _, f := range files {
		spec, err := loadHost(f, elems)
		if err != nil {
			return nil, err
		}
		selected := map[string]bool{}
		for _, u := range spec.users {
			axioms := map[string]string{}
			if spec.machine != "" {
				axioms[spec.machine] = "machine"
			}
			for _, p := range u.purposes {
				axioms[p] = "purposes"
			}
			for n := range derive(elems, axioms) {
				selected[n] = true
			}
		}
		for _, n := range names {
			if n == allElements || n == hostElement || n == machinesElement || n == userElement || selected[n] {
				hosts = append(hosts, strings.TrimSuffix(filepath.Base(f), ".toml"))
				break
			}
		}
	}
	return hosts, nil
}
