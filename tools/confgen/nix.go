package main

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
)

func nixString(s string) string {
	return `"` + strings.NewReplacer(`\`, `\\`, `"`, `\"`, "${", `\${`, "\n", `\n`, "\r", `\r`, "\t", `\t`).Replace(s) + `"`
}

func nixInteger(value int64) string {
	if value == math.MinInt64 {
		return "(-9223372036854775807 - 1)"
	}
	return strconv.FormatInt(value, 10)
}

func nixValue(v any, class string) (string, error) {
	switch x := v.(type) {
	case nil:
		return "null", nil
	case string:
		if !utf8.ValidString(x) || strings.ContainsRune(x, 0) {
			return "", fmt.Errorf("Nix strings must be UTF-8 without NUL")
		}
		return nixString(x), nil
	case bool:
		return strconv.FormatBool(x), nil
	case int64:
		return nixInteger(x), nil
	case int:
		return nixInteger(int64(x)), nil
	case float64:
		if math.IsNaN(x) || math.IsInf(x, 0) {
			return "", fmt.Errorf("Nix floats must be finite")
		}
		s := strconv.FormatFloat(x, 'g', -1, 64)
		mantissa, exponent, scientific := strings.Cut(s, "e")
		if !strings.Contains(mantissa, ".") {
			mantissa += ".0"
		}
		s = mantissa
		if scientific {
			s += "e" + exponent
		}
		return s, nil
	case []any:
		parts := []string{}
		for _, item := range x {
			s, err := nixValue(item, class)
			if err != nil {
				return "", err
			}
			parts = append(parts, "("+s+")")
		}
		return "[ " + strings.Join(parts, " ") + " ]", nil
	case map[string]any:
		if len(x) == 1 {
			for k, value := range x {
				if strings.HasPrefix(k, "$") {
					return nixMarker(k, value, class)
				}
			}
		}
		keys := make([]string, 0, len(x))
		for key := range x {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		parts := []string{}
		for _, key := range keys {
			s, err := nixValue(x[key], class)
			if err != nil {
				return "", err
			}
			parts = append(parts, nixString(key)+" = "+s+";")
		}
		return "{ " + strings.Join(parts, " ") + " }", nil
	}
	return "", fmt.Errorf("unsupported Nix value %T", v)
}

func nixMarker(kind string, value any, class string) (string, error) {
	if kind == "$module" || kind == "$repoModule" {
		return "", fmt.Errorf("%s is only allowed in imports", kind)
	}
	if kind == "$kernelPkg" && class != "nixos" {
		return "", fmt.Errorf("kernelPkg can only be used in NixOS settings")
	}
	if kind == "$activation" || kind == "$outOfStoreLink" || kind == "$gvariantTuple" {
		if class != "home" {
			return "", fmt.Errorf("%s cannot be used in %s settings", kind, class)
		}
	}
	unary := map[string]string{
		"$pkg":         "lib.getAttrFromPath (lib.splitString \".\" %s) pkgs",
		"$lua":         "lib.generators.toLua {} %s",
		"$luaPackages": "(ps: map (name: ps.${name}) %s)",
	}
	if template, ok := unary[kind]; ok {
		s, err := nixValue(value, class)
		if err != nil {
			return "", err
		}
		return "(" + fmt.Sprintf(template, "("+s+")") + ")", nil
	}
	if kind == "$concat" {
		s, err := nixValue(value, class)
		if err != nil {
			return "", err
		}
		return "(lib.concatStrings " + s + ")", nil
	}
	templates := map[string]struct {
		arity int
		text  string
	}{
		"$kernelPkg":         {1, "config.boot.kernelPackages.${%s}"},
		"$exe":               {2, "lib.getExe' (lib.getAttrFromPath (lib.splitString \".\" %s) pkgs) %s"},
		"$script":            {2, "pkgs.writeShellScript %s %s"},
		"$scriptBin":         {2, "pkgs.writeShellScriptBin %s %s"},
		"$file":              {2, "pkgs.writeText %s %s"},
		"$shellApp":          {3, "pkgs.writeShellApplication { name = %s; runtimeInputs = %s; text = %s; }"},
		"$shellAppEnv":       {4, "pkgs.writeShellApplication { name = %s; runtimeInputs = %s; runtimeEnv = %s; text = %s; }"},
		"$repoText":          {1, "builtins.readFile (repoRoot + (\"/\" + %s))"},
		"$repoPkgWith":       {2, "pkgs.callPackage (repoRoot + (\"/\" + %s)) %s"},
		"$repoPath":          {1, "repoRoot + (\"/\" + %s)"},
		"$pythonWithModules": {1, "pkgs.python3.withPackages (_: map pkgs.python3Packages.toPythonModule %s)"},
		"$pkgSetFn":          {1, "(ps: map (name: lib.getAttrFromPath (lib.splitString \".\" name) ps) %s)"},
		"$pkgWithPackages":   {2, "(lib.getAttrFromPath (lib.splitString \".\" %s) pkgs).withPackages (ps: map (name: lib.getAttrFromPath (lib.splitString \".\" name) ps) %s)"},
		"$mkAfter":           {1, "lib.mkAfter %s"},
		"$mkBefore":          {1, "lib.mkBefore %s"},
		"$flakeRev":          {0, "inputs.self.rev or inputs.self.dirtyRev or \"unknown\""},
		"$repoPkg":           {1, "pkgs.callPackage (repoRoot + (\"/\" + %s)) {}"},
		"$symlinkJoin":       {2, "pkgs.symlinkJoin { name = %s; paths = %s; }"},
		"$symlinkJoinBuild":  {4, "pkgs.symlinkJoin { name = %s; paths = %s; nativeBuildInputs = %s; postBuild = %s; }"},
		"$toJSON":            {1, "builtins.toJSON %s"},
		"$command":           {2, "pkgs.runCommand %s {} %s"},
		"$inputPkg":          {2, "inputs.${%s}.packages.${pkgs.stdenv.hostPlatform.system}.${%s}"},
		"$outOfStoreLink":    {1, "config.lib.file.mkOutOfStoreSymlink %s"},
		"$activation":        {2, "lib.hm.dag.entryAfter %s %s"},
		"$gvariantTuple":     {1, "lib.hm.gvariant.mkTuple %s"},
	}
	spec, ok := templates[kind]
	if !ok {
		return "", fmt.Errorf("unknown Nix value %s", kind)
	}
	args, ok := value.([]any)
	if !ok || len(args) != spec.arity {
		return "", fmt.Errorf("%s requires %d arguments", kind, spec.arity)
	}
	rendered := make([]any, len(args))
	for i, arg := range args {
		s, err := nixValue(arg, class)
		if err != nil {
			return "", err
		}
		rendered[i] = "(" + s + ")"
	}
	return "(" + fmt.Sprintf(spec.text, rendered...) + ")", nil
}

func nixImport(v any) (string, error) {
	m, ok := v.(map[string]any)
	if !ok {
		return "", fmt.Errorf("invalid module reference")
	}
	if path, ok := m["$repoModule"].(string); ok {
		return "(repoRoot + " + nixString("/"+path) + ")", nil
	}
	if args, ok := m["$module"].([]any); ok && len(args) == 2 {
		input, a := args[0].(string)
		attr, b := args[1].(string)
		if !a || !b {
			return "", fmt.Errorf("invalid external module reference")
		}
		key := "confgen:input:" + strconv.Quote(input) + ":" + strconv.Quote(attr)
		module := "lib.getAttrFromPath (lib.splitString \".\" " + nixString(attr) + ") inputs." + nixString(input)
		return "{ key = " + nixString(key) + "; imports = [ (" + module + ") ]; }", nil
	}
	return "", fmt.Errorf("invalid module reference")
}

func nixModule(elements map[string]outputs, class string) (string, error) {
	names := make([]string, 0, len(elements))
	for name := range elements {
		names = append(names, name)
	}
	sort.Strings(names)
	var out strings.Builder
	out.WriteString("{ imports = [\n")
	for _, name := range names {
		e := elements[name]
		fmt.Fprintf(&out, "({ config, lib, pkgs, ... }: {\n  _file = %s;\n  imports = [\n", nixString("config/elements/"+name+".star"))
		imports, _ := e[class+"_imports"].([]any)
		for _, m := range imports {
			s, err := nixImport(m)
			if err != nil {
				return "", fmt.Errorf("%s: %w", name, err)
			}
			out.WriteString("    " + s + "\n")
		}
		out.WriteString("  ];\n  config = lib.mkMerge [\n")
		settings, _ := e[class].([]setting)
		for _, setting := range settings {
			path := make([]string, len(setting.Path))
			for i, part := range setting.Path {
				path[i] = nixString(part)
			}
			value, err := nixValue(setting.Value, class)
			if err != nil {
				return "", fmt.Errorf("%s: %s: %w", name, strings.Join(setting.Path, "."), err)
			}
			fmt.Fprintf(&out, "    { %s = %s; }\n", strings.Join(path, "."), value)
		}
		out.WriteString("  ];\n})\n")
	}
	out.WriteString("]; }")
	return out.String(), nil
}

func writeNix(r *hostResult, path string) error {
	nixos, err := nixModule(r.Elements, "nixos")
	if err != nil {
		return err
	}
	var out strings.Builder
	fmt.Fprintf(&out, "{ inputs, repoRoot }: {\n  nixos = %s;\n  homes = {\n", nixos)
	users := make([]string, 0, len(r.Users))
	for user := range r.Users {
		users = append(users, user)
	}
	sort.Strings(users)
	for _, user := range users {
		home, err := nixModule(r.Users[user].Elements, "home")
		if err != nil {
			return err
		}
		fmt.Fprintf(&out, "    %s = %s;\n", nixString(user), home)
	}
	out.WriteString("  };\n}\n")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(out.String()), 0o644)
}
