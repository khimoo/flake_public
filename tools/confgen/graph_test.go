package main

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

const linuxHost = "system = \"x86_64-linux\"\n"

func graphOf(t *testing.T, elements, hosts map[string]string) *graphData {
	t.Helper()
	data, err := configGraph(writeConfig(t, elements, hosts))
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func TestGraphNodesAreTheUsersElementsWithTheirRoles(t *testing.T) {
	data := graphOf(t, map[string]string{
		"m":    "kind = \"machine\"\nrequires = [\"fact\"]",
		"fact": `kind = "machine_fact"`,
		"p":    `requires = ["q"]`,
		"q":    "def user_config(host):\n    return {\"home\": {\"linux\": host.linux}}",
	}, map[string]string{"h": linuxHost + "machine = \"m\"\n" + one(`["p"]`)})
	roles := map[string]string{}
	for _, n := range data.Hosts[0].Users[0].Nodes {
		roles[n.ID] = n.Role
	}
	want := map[string]string{"m": "machine", "fact": "fact", "p": "purpose", "q": ""}
	if !reflect.DeepEqual(roles, want) {
		t.Errorf("roles %v, want %v (virtual elements such as host left out)", roles, want)
	}
}

func TestGraphEdgesRecordRequiresReadsAndWrites(t *testing.T) {
	data := graphOf(t, map[string]string{
		"p": `
requires = ["a"]
def user_config(src):
    return {"home": {"x": src.label}}
def writes(sink):
    return [write(sink, "hello")]
`,
		"a":    "",
		"src":  "def public():\n    return {\"label\": \"v\"}",
		"sink": "def user_config(incoming):\n    return {\"home\": {\"received\": [w.value for w in incoming]}}",
	}, map[string]string{"h": linuxHost + one(`["p"]`)})
	want := []graphEdge{{"p", "a", "requires"}, {"p", "src", "reads"}, {"p", "sink", "writes"}}
	if got := data.Hosts[0].Users[0].Edges; !reflect.DeepEqual(got, want) {
		t.Errorf("edges %v, want %v", got, want)
	}
}

func TestGraphShowsNixosSettingsPerHostAndHomeSettingsPerUser(t *testing.T) {
	data := graphOf(t, map[string]string{
		"p": `
def config():
    return {"nixos_imports": [repoModule("hardware.nix"), module("input", "attr")], "nixos": {"boot.foo": True}}
def user_config():
    return {"home": {
        "home.packages": [pkg("git")],
        "lua": luaPackages(["lpeg"]),
        ("home", "file", ".local/x.desktop", "text"): "x",
    }}
`,
	}, map[string]string{"h": linuxHost + one(`["p"]`)})
	h := data.Hosts[0]
	wantNixos := []graphSetting{{"import", `repoModule("hardware.nix")`}, {"import", `module("input", "attr")`}, {"boot.foo", "True"}}
	if !reflect.DeepEqual(h.NixOS["p"], wantNixos) {
		t.Errorf("nixos %v, want %v", h.NixOS["p"], wantNixos)
	}
	home := map[string]string{}
	for _, s := range h.Users[0].Nodes[0].Home {
		home[s.Path] = s.Value
	}
	wantHome := map[string]string{"home.packages": `[pkg("git")]`, "lua": `luaPackages(["lpeg"])`, `home.file.".local/x.desktop".text`: `"x"`}
	if !reflect.DeepEqual(home, wantHome) {
		t.Errorf("home %v, want %v", home, wantHome)
	}
}

func TestGraphWritesLongAndMultilineValuesOneItemPerLine(t *testing.T) {
	long := strings.Repeat("あ", 90)
	data := graphOf(t, map[string]string{
		"p": "def user_config():\n    return {\"home\": {\"long\": [\"" + long + "\"], \"lines\": {\"text\": \"one\\ntwo\"}}}",
	}, map[string]string{"h": linuxHost + one(`["p"]`)})
	home := map[string]string{}
	for _, s := range data.Hosts[0].Users[0].Nodes[0].Home {
		home[s.Path] = s.Value
	}
	want := map[string]string{"long": "[\n  \"" + long + "\"\n]", "lines": "{\n  \"text\": ''\none\ntwo\n  ''\n}"}
	if !reflect.DeepEqual(home, want) {
		t.Errorf("home %q, want %q", home, want)
	}
}

func TestGraphListsHostsInNameOrderAndUsersInFileOrder(t *testing.T) {
	host := linuxHost + "[[users]]\nname = \"z\"\npurposes = [\"a\"]\n[[users]]\nname = \"b\"\npurposes = [\"a\"]\n"
	data := graphOf(t, map[string]string{"a": ""}, map[string]string{"y": host, "x": host})
	var got []string
	for _, h := range data.Hosts {
		for _, u := range h.Users {
			got = append(got, h.Name+"/"+u.Name)
		}
	}
	if want := []string{"x/z", "x/b", "y/z", "y/b"}; !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestGraphMissingSystemNamesTheHostFile(t *testing.T) {
	dir := writeConfig(t, map[string]string{"p": ""}, map[string]string{"missing": one(`["p"]`)})
	if _, err := configGraph(dir); err == nil || !strings.Contains(err.Error(), "missing.toml") || !strings.Contains(err.Error(), "system") {
		t.Fatalf("got %v, want an error naming missing.toml and system", err)
	}
}

func TestGraphOptionsListsDistinctOptionPathsPerHostAndUser(t *testing.T) {
	dir := writeConfig(t, map[string]string{
		"p": `
requires = ["q"]
def config():
    return {"nixos_imports": [repoModule("hardware.nix")], "nixos": {"boot.foo": True}}
def user_config():
    return {"home_imports": [repoModule("home.nix")], "home": {
        ("home", "file", ".local/x.desktop", "text"): "x",
    }}
`,
		"q": `
def config():
    return {"nixos": {"boot.foo": True}}
def user_config():
    return {"home": {("home", "file", ".local/x.desktop", "text"): "x"}}
`,
		"r": "def user_config():\n    return {\"home\": {\"home.stateVersion\": \"25.05\"}}",
	}, map[string]string{
		"h":     linuxHost + one(`["p"]`) + "[[users]]\nname = \"other\"\npurposes = [\"r\"]\n",
		"empty": linuxHost + one("[]"),
	})
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	defer writer.Close()
	stdout := os.Stdout
	os.Stdout = writer
	runErr := run([]string{"graph-options", dir})
	os.Stdout = stdout
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	if runErr != nil {
		t.Fatal(runErr)
	}
	raw, err := io.ReadAll(reader)
	if err != nil {
		t.Fatal(err)
	}
	assertGraphJSON(t, raw, `{
		"h": {
			"nixos": [{"display": "boot.foo", "parts": ["boot", "foo"]}],
			"users": {
				"test": [{"display": "home.file.\".local/x.desktop\".text", "parts": ["home", "file", ".local/x.desktop", "text"]}],
				"other": [{"display": "home.stateVersion", "parts": ["home", "stateVersion"]}]
			}
		},
		"empty": {"nixos": [], "users": {"test": []}}
	}`)
}

func TestGraphPageEmbedsGraphFinalValuesAndReadableSourcesSafely(t *testing.T) {
	element := "def user_config():\n    return {\"home\": {\"text\": \"</ScRiPt><script>alert(1)</script>\"}}"
	host := linuxHost + one(`["p"]`)
	dir := writeConfig(t, map[string]string{"p": element}, map[string]string{"h": host})
	tmp := t.TempDir()
	declaration := filepath.Join(tmp, "module.nix")
	missing := filepath.Join(tmp, "missing.nix")
	module := "{ }\n"
	if err := os.WriteFile(declaration, []byte(module), 0o644); err != nil {
		t.Fatal(err)
	}
	finalPath := filepath.Join(tmp, "final.json")
	final := `{"h":{"nixos":{"boot.foo":true},"users":{"test":{"text":"</script>"},"disabled":null},
		"declarations":{"nixos":{"boot.foo":{"option":"boot.foo","positions":[{"file":` + jsonString(t, missing) + `,"line":1}]}},
		"users":{"test":{"text":{"option":"text","positions":[{"file":` + jsonString(t, declaration) + `,"line":1}]}},
		"disabled":null}}}}`
	if err := os.WriteFile(finalPath, []byte(final), 0o644); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(tmp, "graph.html")
	if err := run([]string{"graph", dir, finalPath, path}); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	page := string(raw)
	if !strings.Contains(page, "cytoscape@3.34.4/") || strings.Contains(page, "dagre") {
		t.Error("page should load Cytoscape 3.34.4 without Dagre")
	}
	_, rest, found := strings.Cut(page, `<script type="application/json" id="confgen-data">`)
	embedded, _, closed := strings.Cut(rest, "</script>")
	if !found || !closed || strings.Contains(strings.ToLower(embedded), "</script>") {
		t.Fatal("invalid JSON script element")
	}
	graph, err := configGraph(dir)
	if err != nil {
		t.Fatal(err)
	}
	want := `{"hosts":` + jsonString(t, graph.Hosts) + `,"final":` + final +
		`,"sources":` + jsonString(t, map[string]string{"config/hosts/h.toml": host, "config/elements/p.star": element}) +
		`,"declaring":` + jsonString(t, map[string]string{declaration: module}) + `}`
	assertGraphJSON(t, []byte(embedded), want)
}

func TestGraphNamesUnreadableFinalJSON(t *testing.T) {
	dir := writeConfig(t, map[string]string{"p": ""}, map[string]string{"h": linuxHost + one(`["p"]`)})
	tmp := t.TempDir()
	final := filepath.Join(tmp, "missing.json")
	err := run([]string{"graph", dir, final, filepath.Join(tmp, "graph.html")})
	if err == nil || !strings.Contains(err.Error(), final) {
		t.Fatalf("got %v, want an error naming %s", err, final)
	}
}

func jsonString(t *testing.T, value any) string {
	t.Helper()
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

func assertGraphJSON(t *testing.T, raw []byte, expected string) {
	t.Helper()
	var got, want any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("output is not JSON: %v", err)
	}
	if err := json.Unmarshal([]byte(expected), &want); err != nil {
		t.Fatalf("invalid expectation: %v", err)
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %s, want %s", raw, expected)
	}
}

func TestGraphValueWritesHelpersAsTheirCalls(t *testing.T) {
	tests := []struct {
		value any
		want  string
	}{
		{nil, "None"}, {true, "True"}, {false, "False"}, {int64(3), "3"}, {1.5, "1.5"},
		{map[string]any{"z": nil, "a": []any{true, "s"}}, `{"a": [True, "s"], "z": None}`},
		{map[string]any{"$concat": []any{"a", "b"}}, `concat(["a", "b"])`},
		{map[string]any{"$mkAfter": []any{[]any{"a"}}}, `mkAfter(["a"])`},
		{map[string]any{"$flakeRev": []any{}}, `flakeRev()`},
	}
	for _, tt := range tests {
		if got, err := graphValue(tt.value, false, 0); err != nil || got != tt.want {
			t.Errorf("%#v: got %q, %v; want %q", tt.value, got, err, tt.want)
		}
	}
}
