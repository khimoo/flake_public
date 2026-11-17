package main

import (
	"math"
	"os"
	"strings"
	"testing"
)

func TestNixRejectsValuesThatCannotBeLiteralData(t *testing.T) {
	for name, value := range map[string]any{
		"invalid UTF-8":             string([]byte{0xff}),
		"NUL":                       "a\x00b",
		"NaN":                       math.NaN(),
		"infinity":                  math.Inf(1),
		"unknown expression":        map[string]any{"$nix": "builtins.readFile /etc/passwd"},
		"nested unknown expression": []any{map[string]any{"$nix": "builtins.currentTime"}},
		"module as a value":         map[string]any{"$module": []any{"x", "nixosModules.default"}},
		"wrong helper arity":        map[string]any{"$file": []any{"name"}},
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := nixValue(value, "nixos"); err == nil {
				t.Fatal("accepted a value outside the supported Nix expressions")
			}
		})
	}
}

func TestNixRejectsHelpersOutsideTheirModuleClass(t *testing.T) {
	for _, kind := range []string{"$activation", "$outOfStoreLink", "$gvariantTuple"} {
		if _, err := nixValue(map[string]any{kind: []any{}}, "nixos"); err == nil {
			t.Fatalf("accepted %s in NixOS", kind)
		}
	}
	if _, err := nixValue(map[string]any{"$kernelPkg": []any{"v4l2loopback"}}, "home"); err == nil {
		t.Fatal("accepted a kernel package in Home Manager")
	}
}

func TestWhyLabelsOptionsSharedAcrossUsers(t *testing.T) {
	dir := writeConfig(t, map[string]string{"shared": `
def user_config(user):
    return {"home": {("home", "file", user.name, "text"): "value"}}
`}, map[string]string{"h": `
[[users]]
name = "alice"
purposes = ["shared"]
[[users]]
name = "bob"
purposes = ["shared"]
`})
	output, err := os.CreateTemp(t.TempDir(), "why")
	if err != nil {
		t.Fatal(err)
	}
	defer output.Close()
	previous := os.Stdout
	os.Stdout = output
	defer func() { os.Stdout = previous }()
	if err := why(dir, "h", "x86_64-linux", "alice", "shared"); err != nil {
		t.Fatal(err)
	}
	os.Stdout = previous
	text, err := os.ReadFile(output.Name())
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{"host-wide options (all users):", "home:home.file.alice.text", "home:home.file.bob.text"} {
		if !strings.Contains(string(text), expected) {
			t.Fatalf("missing %q in %s", expected, text)
		}
	}
}
