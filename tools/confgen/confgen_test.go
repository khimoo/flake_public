package main

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// writeConfig lays out config/elements/*.star and config/hosts/*.toml in a temp dir.
func writeConfig(t *testing.T, elements map[string]string, hosts map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for sub, files := range map[string]map[string]string{"elements": elements, "hosts": hosts} {
		ext := map[string]string{"elements": ".star", "hosts": ".toml"}[sub]
		if err := os.MkdirAll(filepath.Join(dir, sub), 0o755); err != nil {
			t.Fatal(err)
		}
		for name, src := range files {
			if err := os.WriteFile(filepath.Join(dir, sub, name+ext), []byte(src), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
	return dir
}

// one is a host file whose only user, test, selects purposes.
func one(purposes string) string {
	return "[[users]]\nname = \"test\"\npurposes = " + purposes + "\n"
}

func buildHosts(t *testing.T, elements, hosts map[string]string) map[string]*hostResult {
	t.Helper()
	dir := writeConfig(t, elements, hosts)
	out := map[string]*hostResult{}
	for h := range hosts {
		r, err := buildHost(dir, h, "x86_64-linux")
		if err != nil {
			t.Fatal(err)
		}
		out[h] = r
	}
	return out
}

func buildError(t *testing.T, elements map[string]string) string {
	t.Helper()
	_, err := buildHost(writeConfig(t, elements, map[string]string{"h": one(`["p"]`)}), "h", "x86_64-linux")
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
		"both":   one(`["a", "b"]`),
		"b_only": one(`["b"]`),
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
		"xy": one(`["x", "y"]`),
		"x":  one(`["x"]`),
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
def user_config(incoming):
    return {"home": {"x.y": [w.value for w in incoming]}}
`,
		"p": `
def writes(sink):
    return [write(sink, {"copy": sink.label})]
`,
	}
	r := buildHosts(t, elements, map[string]string{"h": one(`["p"]`)})
	g := r["h"].Graph["p"]
	if !reflect.DeepEqual(g.Reads, []string{"sink"}) || !reflect.DeepEqual(g.Writes, []string{"sink"}) {
		t.Errorf("reads %v writes %v, want sink in both", g.Reads, g.Writes)
	}
}

func TestHostFactsDescribeTheBuiltSystem(t *testing.T) {
	dir := writeConfig(t, map[string]string{
		"p": "def user_config(host, user):\n    return {\"home\": {\"a\": host.linux, (\"b\", \"c.d\"): host.system, \"h\": user.home}}",
	}, map[string]string{"h": "[[users]]\nname = \"alice\"\npurposes = [\"p\"]\n"})
	r, err := buildHost(dir, "h", "aarch64-darwin")
	if err != nil {
		t.Fatal(err)
	}
	got := r.Users["alice"].Elements["p"]["home"]
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
			"p": "def user_config():\n    return {\"home\": {\"a\": \"run %s\" % exe(\"x\", \"y\")}}"}, "turned into text"},
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

func TestAffectedCoversReadersWriteTargetsAndDerivedElementsOnly(t *testing.T) {
	root := t.TempDir()
	config := writeConfig(t, map[string]string{
		"a":         `def public(): return {"x": 1}`,
		"reads_a":   "def user_config(a):\n    return {\"home\": {\"x\": a.x}}",
		"sink":      "def user_config(incoming):\n    return {\"home\": {\"n\": len(incoming)}}",
		"writes":    "def writes(sink):\n    return [write(sink, 1)]",
		"derived":   `when = ["a", "sink"]`,
		"unrelated": "def user_config(host):\n    return {\"home\": {\"s\": host.system}}",
		"uses_pkg":  "def user_config():\n    return {\"home\": {\"p\": repoPkg(\"packages/foo\")}}",
	}, map[string]string{"h": one(`["a"]`)})
	if err := os.Symlink(config, filepath.Join(root, "config")); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct {
		paths []string
		want  []string
	}{
		{[]string{"config/elements/a.star"}, []string{"a", "derived", "reads_a"}},
		{[]string{"config/elements/writes.star"}, []string{"sink", "writes"}},
		{[]string{"config/hosts/h.toml"}, []string{"host", "machines", "unrelated", "user"}},
		{[]string{"packages/foo/default.nix"}, []string{"uses_pkg"}},
		{[]string{"docs/x.md"}, nil},
		{[]string{"lib/confgen.nix"}, []string{allElements}},
	} {
		got, err := affected(root, c.paths)
		if err != nil {
			t.Fatal(err)
		}
		if len(got) == 0 && len(c.want) == 0 {
			continue
		}
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("affected(%v) = %v, want %v", c.paths, got, c.want)
		}
	}
	for _, c := range []struct {
		names []string
		want  []string
	}{
		{[]string{"a"}, []string{"h"}},
		{[]string{"unrelated"}, nil},
		{[]string{"host"}, []string{"h"}},
		{[]string{allElements}, []string{"h"}},
	} {
		got, err := affectedHosts(root, c.names)
		if err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(nonNil(got), nonNil(c.want)) {
			t.Errorf("affectedHosts(%v) = %v, want %v", c.names, got, c.want)
		}
	}
}

func TestAloneReportsElementsThatFailWithoutAnotherSelectedElement(t *testing.T) {
	dir := writeConfig(t, map[string]string{
		"sink": `
def config(incoming):
    if len(incoming) == 1:
        fail("sink: half of the pair")
    return {"nixos": {"n": len(incoming)}}
`,
		"needs_partner": "def writes(sink):\n    return [write(sink, 1)]",
		"partner":       "def writes(sink):\n    return [write(sink, 2)]",
		"never_chosen":  ``,
		"derived":       `when = ["needs_partner", "partner"]`,
	}, map[string]string{
		"h":        one(`["needs_partner", "partner"]`),
		"rejected": one(`["needs_partner"]`),
	})
	failures, err := alone(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(failures) != 3 ||
		!strings.HasPrefix(failures[0], "needs_partner alone (values of host h)") ||
		!strings.HasPrefix(failures[1], "partner alone (values of host h)") ||
		!strings.HasPrefix(failures[2], "never_chosen: no host generates it") {
		t.Errorf("failures %q", failures)
	}
}

func TestEachUserGetsTheElementsItsOwnPurposesDerive(t *testing.T) {
	elements := map[string]string{
		"m":      "kind = \"machine\"\nrequires = [\"base\"]",
		"base":   "def user_config(user):\n    return {\"home\": {\"who\": user.name}}",
		"a":      `requires = ["only_a"]`,
		"only_a": "def user_config():\n    return {\"home\": {\"a\": True}}",
		"b":      ``,
		"d":      `when = ["a", "b"]` + "\ndef config():\n    return {\"nixos\": {\"d\": True}}",
	}
	r := buildHosts(t, elements, map[string]string{"h": `machine = "m"
[[users]]
name = "alice"
purposes = ["a"]
[[users]]
name = "bob"
purposes = ["b"]
`})["h"]
	if got, want := r.Users["alice"].Generated, []string{"a", "base", "m", "only_a", "user"}; !reflect.DeepEqual(got, want) {
		t.Errorf("alice: %v, want %v", got, want)
	}
	if got, want := r.Users["bob"].Generated, []string{"b", "base", "m", "user"}; !reflect.DeepEqual(got, want) {
		t.Errorf("bob: %v, want %v", got, want)
	}
	// d needs a and b for the same user; alice has a and bob has b.
	if got, want := r.Generated, []string{"a", "b", "base", "m", "only_a", "user"}; !reflect.DeepEqual(got, want) {
		t.Errorf("host: %v, want %v", got, want)
	}
	if _, ok := r.Users["bob"].Elements["only_a"]; ok {
		t.Errorf("bob got the settings of only_a")
	}
	if got, want := r.Users["alice"].Reasons["only_a"], (reason{Rule: "requires", From: []string{"a"}}); !reflect.DeepEqual(got, want) {
		t.Errorf("reason of only_a: %#v, want %#v", got, want)
	}
	if got, want := r.Users["bob"].Reasons["m"], (reason{Axiom: "machine"}); !reflect.DeepEqual(got, want) {
		t.Errorf("reason of m: %#v, want %#v", got, want)
	}
}

func TestPerUserNixosSettingsJoinTheHostSettings(t *testing.T) {
	elements := map[string]string{
		"audio": `
def config():
    return {"nixos": {"sound": True}}
def user_config(user):
    return {"nixos": {("users", "users", user.name, "extraGroups"): ["audio"]}}
`,
	}
	r := buildHosts(t, elements, map[string]string{"h": `
[[users]]
name = "alice"
purposes = ["audio"]
[[users]]
name = "bob"
purposes = []
`})["h"]
	got := r.Elements["audio"]["nixos"]
	want := []setting{{Path: []string{"sound"}, Value: true}, {Path: []string{"users", "users", "alice", "extraGroups"}, Value: []any{"audio"}}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %#v, want %#v", got, want)
	}
}

func TestPurposesAreNotValuesElementsCanRead(t *testing.T) {
	elements := map[string]string{
		"p": `
def user_config(host, machines):
    return {"home": {
        "host": "purposes" in host.users[0],
        "machines": "purposes" in machines.all["h"]["users"][0],
        "machine": "machine" in machines.all["h"],
    }}
`,
		"m": `kind = "machine"`,
	}
	r := buildHosts(t, elements, map[string]string{"h": "machine = \"m\"\n" + one(`["p"]`)})["h"]
	got := r.Users["test"].Elements["p"]["home"]
	want := []setting{{Path: []string{"host"}, Value: false}, {Path: []string{"machine"}, Value: false}, {Path: []string{"machines"}, Value: false}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %#v, want %#v", got, want)
	}
}

func TestRejectedForRulesAAndB(t *testing.T) {
	cases := []struct {
		name     string
		elements map[string]string
		host     string
		want     string
	}{
		{"config reads user", map[string]string{
			"p": "def config(user):\n    return {\"nixos\": {\"a\": user.name}}"}, one(`["p"]`), "differs per user"},
		{"config reads a public value made from user", map[string]string{
			"p": "def config(q):\n    return {\"nixos\": {\"a\": q.home}}",
			"q": "def public(user):\n    return {\"home\": user.home}"}, one(`["p"]`), "differs per user"},
		{"config sets home options", map[string]string{
			"p": "def config():\n    return {\"home\": {\"a\": 1}}"}, one(`["p"]`), "config keys must be nixos"},
		{"config returns nothing", map[string]string{
			"p": "def config(host):\n    return {} if host.linux else {\"nixos\": {\"a\": 1}}"}, one(`["p"]`), "produced no settings"},
		{"user_config returns nothing for one user", map[string]string{
			"p": "def user_config(user):\n    return {} if user.name == \"bob\" else {\"home\": {\"a\": 1}}"},
			"[[users]]\nname = \"alice\"\npurposes = [\"p\"]\n[[users]]\nname = \"bob\"\npurposes = [\"p\"]\n", "for user bob"},
		{"writes returns nothing", map[string]string{
			"p":    "def writes(sink, host):\n    return [] if host.linux else [write(sink, 1)]",
			"sink": "def user_config(incoming):\n    return {\"home\": {\"n\": len(incoming)}}"}, one(`["p"]`), "produced no settings"},
		{"per-user writes into config only", map[string]string{
			"p":    "def writes(sink, user):\n    return [write(sink, user.name)]",
			"sink": "def config(incoming):\n    return {\"nixos\": {\"n\": len(incoming)}}"}, one(`["p"]`), "no user_config"},
		{"purposes at the top of the host file", map[string]string{"p": ``}, `purposes = ["p"]`, "belongs to each [[users]]"},
		{"derived element as machine", map[string]string{
			"d": `when = ["a", "b"]`, "a": ``, "b": ``}, "machine = \"d\"\n" + one(`[]`), "derived"},
		{"user without purposes", map[string]string{"p": ``}, "[[users]]\nname = \"test\"\n", "has no purposes"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := buildHost(writeConfig(t, c.elements, map[string]string{"h": c.host}), "h", "x86_64-linux")
			if err == nil {
				t.Fatal("build succeeded, want an error")
			}
			if !strings.Contains(err.Error(), c.want) {
				t.Errorf("error %q does not mention %q", err, c.want)
			}
		})
	}
}

// machineHost is a host file whose machine element is m and whose only user, test, selects purposes.
func machineHost(m, purposes string) string {
	return "machine = \"" + m + "\"\n" + one(purposes)
}

func TestMachineFactsGateDerivedElementsWithoutNamingTheMachine(t *testing.T) {
	elements := map[string]string{
		"desk":          "kind = \"machine\"\nrequires = [\"keep_archive\"]",
		"laptop":        `kind = "machine"`,
		"keep_archive":  `kind = "machine_fact"`,
		"read":          ``,
		"pull":          ``,
		"pull_for_read": "when = [\"read\", \"keep_archive\"]\nrequires = [\"pull\"]",
	}
	r := buildHosts(t, elements, map[string]string{
		"d": machineHost("desk", `["read"]`),
		"l": machineHost("laptop", `["read"]`),
	})
	if got, want := r["d"].Generated, []string{"desk", "keep_archive", "pull", "pull_for_read", "read"}; !reflect.DeepEqual(got, want) {
		t.Errorf("desk: %v, want %v", got, want)
	}
	if got, want := r["l"].Generated, []string{"laptop", "read"}; !reflect.DeepEqual(got, want) {
		t.Errorf("laptop: %v, want %v", got, want)
	}
}

func TestNeedsStopsTheBuildWithoutMakingTheFactTrue(t *testing.T) {
	elements := map[string]string{
		"desk":      "kind = \"machine\"\nrequires = [\"local_kvm\"]",
		"wsl":       `kind = "machine"`,
		"local_kvm": `kind = "machine_fact"`,
		"use_vm":    `requires = ["vm"]`,
		"vm":        `needs = ["local_kvm"]`,
	}
	dir := writeConfig(t, elements, map[string]string{
		"d": machineHost("desk", `["use_vm"]`),
		"w": machineHost("wsl", `["use_vm"]`),
	})
	if _, err := buildHost(dir, "d", "x86_64-linux"); err != nil {
		t.Fatalf("desk: %v", err)
	}
	_, err := buildHost(dir, "w", "x86_64-linux")
	if err == nil {
		t.Fatal("wsl: build succeeded, want an error")
	}
	for _, want := range []string{"use_vm → vm", "needs local_kvm"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q does not mention %q", err, want)
		}
	}
}

func TestRejectedForMachineDescriptions(t *testing.T) {
	cases := []struct {
		name     string
		elements map[string]string
		host     string
		want     string
	}{
		{"action requires a fact", map[string]string{
			"p": `requires = ["kvm"]`, "kvm": `kind = "machine_fact"`}, one(`["p"]`), "describes the machine"},
		{"when names the machine element", map[string]string{
			"p": ``, "m": `kind = "machine"`, "d": `when = ["p", "m"]`}, one(`["p"]`), "names the machine element"},
		{"machine key names an ordinary element", map[string]string{
			"p": ``, "m": ``}, machineHost("m", `["p"]`), "kind = \"machine\""},
		{"fact listed in purposes on a host with a machine", map[string]string{
			"p": ``, "m": `kind = "machine"`, "kvm": `kind = "machine_fact"`}, machineHost("m", `["kvm"]`), "require it from the machine element"},
		{"machine element listed in purposes", map[string]string{
			"p": ``, "m": `kind = "machine"`}, one(`["m"]`), "write it as machine"},
		{"unknown kind", map[string]string{
			"p": `kind = "action"`}, one(`["p"]`), "kind must be"},
		{"unknown element in needs", map[string]string{
			"p": `needs = ["kvm"]`}, one(`["p"]`), "in needs"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := buildHost(writeConfig(t, c.elements, map[string]string{"h": c.host}), "h", "x86_64-linux")
			if err == nil || !strings.Contains(err.Error(), c.want) {
				t.Errorf("error %v does not mention %q", err, c.want)
			}
		})
	}
}

func TestHostWithoutMachineListsFactsInPurposes(t *testing.T) {
	elements := map[string]string{
		"kvm": `kind = "machine_fact"`,
		"vm":  `needs = ["kvm"]`,
	}
	r := buildHosts(t, elements, map[string]string{"t": one(`["vm", "kvm"]`)})
	if got, want := r["t"].Generated, []string{"kvm", "vm"}; !reflect.DeepEqual(got, want) {
		t.Errorf("%v, want %v", got, want)
	}
}
