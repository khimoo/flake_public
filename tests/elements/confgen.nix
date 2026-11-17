{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) inputs rejectsPurpose configDir;
in
{
  generated-nix-contracts =
    (lib.lazyDerivation {
      derivation =
        let
          fixtures = inputs.nixpkgs.legacyPackages.x86_64-linux.runCommand "nix-emitter-fixtures" { } ''
            cp -r ${../confgen} "$out"
            chmod -R u+w "$out"
            cp ${../owner.toml} "$out/owner.toml"
          '';
          generator = import ../../lib/confgen.nix {
            pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
            configDir = fixtures;
          };
          generated =
            host:
            import (generator.generate host "x86_64-linux") {
              inputs = inputs // {
                contract.nixosModules.shared = { ... }: { test.provider = [ "provider" ]; };
              };
              repoRoot = ../..;
            };
          declarations = {
            options.test = {
              scalar = lib.mkOption { type = lib.types.int; };
              integers = lib.mkOption {
                type = lib.types.listOf lib.types.int;
                default = [ ];
              };
              floats = lib.mkOption {
                type = lib.types.listOf lib.types.float;
                default = [ ];
              };
              values = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
              provider = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
              ordered = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
              literal = lib.mkOption {
                type = lib.types.str;
                default = "";
              };
              names = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
              };
            };
          };
          evaluate =
            host:
            lib.evalModules {
              modules = [
                declarations
                (generated host).nixos
              ];
            };
          both = (evaluate "both").config.test;
          one = (evaluate "one").config.test;
          none = (evaluate "none").config.test;
          conflict = builtins.tryEval (evaluate "conflict").config.test.scalar;
          user =
            (lib.evalModules {
              modules = [
                { options.test.home = lib.mkOption { type = lib.types.str; }; }
                (generated "both").homes.test
              ];
            }).config.test.home;
        in
        assert both.scalar == 1;
        assert
          both.integers == [
            (-9223372036854775807 - 1)
            9223372036854775807
          ];
        assert
          both.floats == [
            1000000.0
            0.0000001
            (-100000000000000000000.0)
            1.25e30
            0.0
          ];
        assert
          lib.sort builtins.lessThan both.values == [
            "alpha"
            "beta"
          ];
        assert both.provider == [ "provider" ];
        assert
          both.ordered == [
            "first"
            "last"
          ];
        assert both.names."key.with.dot" == "literal";
        assert both.literal == "日本語 \${throw \"injected\"} \\ \"\n\t";
        assert one.values == [ "beta" ] && one.provider == [ "provider" ];
        assert none.provider == [ ] && none.values == [ ];
        assert !conflict.success;
        assert user == "/home/test";
        pkgs.runCommand "generated-nix-contracts" { } ''touch "$out"'';
    })
    // {
      always = true;
    };

  # どのコンポーネントも、ホストでそれ1つだけを選んで生成できること（docs/architecture/rules.md の規則 A）。
  elements-alone =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "elements-alone"
          {
            nativeBuildInputs = [
              (import ../../lib/confgen.nix {
                pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
                inherit configDir;
              }).package
            ];
          }
          ''
            confgen alone ${configDir}
            touch "$out"
          ''
      );
    })
    // {
      always = true;
    };

  confgen-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert rejectsPurpose "test-bad-purpose-type" "x86_64-linux"
          "purposes must be a list of element names";
        assert rejectsPurpose "test-unknown-purpose" "x86_64-linux" "unknown element";
        pkgs.runCommand "confgen-contracts" { } ''
          echo "confgen contracts passed" > "$out"
        ''
      );
    })
    // {
      always = true;
    };

  docs =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "documentation-links" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          python ${../../scripts/check-docs.py} ${../../.}
          touch "$out"
        ''
      );
    })
    // {
      always = true;
    };

  graphify-smoke =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "graphify-smoke"
          {
            nativeBuildInputs = [
              pkgs.python3
              inputs.nixpkgs-unstable.legacyPackages.${system}.graphify
            ];
          }
          ''
            export HOME="$TMPDIR"
            python ${../graphify-smoke.py}
            touch "$out"
          ''
      );
    })
    // {
      always = true;
    };
  # コミット前の hook が、ステージした docs/howtouse の文書だけを校正し、印があれば通し、校正に失敗したら止めること。
  proofread-howtouse =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "proofread-howtouse"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.git
            ];
          }
          ''
            python ${../proofread-howtouse.py} ${../../.agents/hooks/proofread-howtouse.py}
            touch "$out"
          ''
      );
    })
    // {
      always = true;
    };
}
