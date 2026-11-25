{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) home purposeHome;
in
{
  gui-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert
          system != "x86_64-linux"
          ||
            builtins.any (p: (p.pname or "") == "kitty")
              (purposeHome system "test-gui").config.home.packages;
        assert !(purposeHome system "test-gui").config.programs.firefox.enable;
        assert !(purposeHome system "test-gui").config.programs.anki.enable;
        assert
          !builtins.any (p: (p.pname or "") == "zen-beta")
            (purposeHome system "test-gui").config.home.packages;
        pkgs.runCommand "gui-contracts" { } ''
          echo "gui contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "gui"
        "kitty"
      ];
    };
}
