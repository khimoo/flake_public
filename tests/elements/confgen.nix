{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) inputs rejectsPurpose;
in
{
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
