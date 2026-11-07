package main

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// writeConfig lays out config/elements/*.star and config/hosts/*.star in a temp dir.
func writeConfig(t *testing.T, elements map[string]string, hosts map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for sub, files := range map[string]map[string]string{"elements": elements, "hosts": hosts} {
		if err := os.MkdirAll(filepath.Join(dir, sub), 0o755); err != nil {
			t.Fatal(err)
		}
		for name, src := range files {
			if err := os.WriteFile(filepath.Join(dir, sub, name+".star"), []byte(src), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
	return dir
}

func buildHosts(t *testing.T, elements, hosts map[string]string) map[string]*hostResult {
	t.Helper()
	dir := writeConfig(t, elements, hosts)
	out := map[string]*hostResult{}
	for h := range hosts {
		r, err := buildHost(dir, h, "x86_64-linux", "test")
		if err != nil {
			t.Fatal(err)
		}
		out[h] = r
	}
	return out
}

func buildError(t *testing.T, elements map[string]string) string {
	t.Helper()
	_, err := buildHost(writeConfig(t, elements, map[string]string{"h": `purposes = ["p"]`}), "h", "x86_64-linux", "test")
	if err == nil {
		t.Fatal("build succeeded, want an error")
	}
	return err.Error()
}

func TestRemovingPurposeRemovesItsElementsAndKeepsSharedOnes(t *testing.T) {
	elements := map[string]string{
		"a":      `requires = ["only_a", "shared"]`,
		"b":      `requires = ["shared"]`,
		"only_a": ``,
		"shared": ``,
	}
	r := buildHosts(t, elements, map[string]string{
		"both":   `purposes = ["a", "b"]`,
		"b_only": `purposes = ["b"]`,
	})
	if got, want := r["both"].Generated, []string{"a", "b", "only_a", "shared"}; !reflect.DeepEqual(got, want) {
		t.Errorf("both: %v, want %v", got, want)
	}
	if got, want := r["b_only"].Generated, []string{"b", "shared"}; !reflect.DeepEqual(got, want) {
		t.Errorf("b_only: %v, want %v", got, want)
	}
}

func TestDerivedElementIsGeneratedOnlyWhenAllConditionsAre(t *testing.T) {
	elements := map[string]string{
		"x":  ``,
		"y":  ``,
		"z":  ``,
		"d":  `when = ["x", "y"]` + "\nrequires = [\"z\"]",
		"e":  `when = ["d", "z"]`, // chains on d and on z, which only d brings in
		"m1": `when = ["m2", "x"]`,
		"m2": `when = ["m1", "x"]`, // each needs the other: never generated
	}
	r := buildHosts(t, elements, map[string]string{
		"xy": `purposes = ["x", "y"]`,
		"x":  `purposes = ["x"]`,
	})
	if got, want := r["xy"].Generated, []string{"d", "e", "x", "y", "z"}; !reflect.DeepEqual(got, want) {
		t.Errorf("xy: %v, want %v", got, want)
	}
	if got, want := r["x"].Generated, []string{"x"}; !reflect.DeepEqual(got, want) {
		t.Errorf("x: %v, want %v", got, want)
	}
}

func TestReadingAndWritingTheSameElementRecordsBoth(t *testing.T) {
	elements := map[string]string{
		"sink": `
def public():
    return {"label": "v1"}
def config(incoming):
    return {"home": {"x.y": [w.value for w in incoming]}}
`,
		"p": `
def writes(sink):
    return [write(sink, {"copy": sink.label})]
`,
	}
	r := buildHosts(t, elements, map[string]string{"h": `purposes = ["p"]`})
	g := r["h"].Graph["p"]
	if !reflect.DeepEqual(g.Reads, []string{"sink"}) || !reflect.DeepEqual(g.Writes, []string{"sink"}) {
		t.Errorf("reads %v writes %v, want sink in both", g.Reads, g.Writes)
	}
}

func TestHostFactsDescribeTheBuiltSystem(t *testing.T) {
	dir := writeConfig(t, map[string]string{
		"p": "def config(host, user):\n    return {\"home\": {\"a\": host.linux, (\"b\", \"c.d\"): host.system, \"h\": user.home}}",
	}, map[string]string{"h": `purposes = ["p"]`})
	r, err := buildHost(dir, "h", "aarch64-darwin", "alice")
	if err != nil {
		t.Fatal(err)
	}
	got := r.Elements["p"]["home"]
	want := []setting{{Path: []string{"a"}, Value: false}, {Path: []string{"b", "c.d"}, Value: "aarch64-darwin"}, {Path: []string{"h"}, Value: "/Users/alice"}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %#v, want %#v", got, want)
	}
}

func TestRejected(t *testing.T) {
	cases := []struct {
		name     string
		elements map[string]string
		want     string
	}{
		{"unused parameter", map[string]string{
			"p": "def config(q):\n    return {}", "q": ``}, "never read"},
		{"parameter only shadowed by lambda and comprehension", map[string]string{
			"p": "def config(q):\n    _a = lambda q: q\n    _b = [q for q in [1]]\n    return {}", "q": ``}, "never read"},
		{"parameter only assigned", map[string]string{
			"p": "def config(q):\n    q = 1\n    return {}", "q": ``}, "never read"},
		{"undeclared element", map[string]string{
			"p": "def config():\n    return {\"home\": {\"a\": q.x}}", "q": ``}, "undefined"},
		{"derived element as parameter", map[string]string{
			"p": "def config(d):\n    return {\"home\": {\"a\": d.x}}", "d": `when = ["a", "b"]`, "a": ``, "b": ``}, "derived"},
		{"derived element in requires", map[string]string{
			"p": `requires = ["d"]`, "d": `when = ["a", "b"]`, "a": ``, "b": ``}, "derived"},
		{"when with one element", map[string]string{
			"p": ``, "d": `when = ["p"]`}, "at least two"},
		{"load", map[string]string{
			"p": `load("q.star", "x")`}, "load"},
		{"write target that is not a parameter", map[string]string{
			"p":      "def writes(broker):\n    return [write(broker.sink, 1)]",
			"broker": ``}, "parameter of writes"},
		{"element reference forwarded through public", map[string]string{
			"p":      `requires = ["broker"]`,
			"broker": "def public(target):\n    return {\"sink\": target}",
			"target": ``}, "element reference"},
		{"public value mutated by a reader", map[string]string{
			"p":    "def writes(base):\n    base.items.append(1)\n    return []",
			"base": "def public():\n    return {\"items\": []}"}, "frozen"},
		{"marker turned into text", map[string]string{
			"p": "def config():\n    return {\"home\": {\"a\": \"run %s\" % exe(\"x\", \"y\")}}"}, "turned into text"},
		{"element named host", map[string]string{
			"p": ``, "host": ``}, "reserved"},
		{"element named user", map[string]string{
			"p": ``, "user": ``}, "reserved"},
		{"write outside writes", map[string]string{
			"p": "def config(q):\n    return {\"home\": {\"a\": write(q, 1)}}", "q": ``}, "only be called inside writes"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := buildError(t, c.elements); !strings.Contains(got, c.want) {
				t.Errorf("error %q does not mention %q", got, c.want)
			}
		})
	}
}
