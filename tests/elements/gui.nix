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
              (purposeHome system "test-gnome").config.home.packages;
        assert !(purposeHome system "test-gnome").config.programs.firefox.enable;
        assert !(purposeHome system "test-gnome").config.programs.anki.enable;
        assert
          !builtins.any (p: (p.pname or "") == "zen-beta")
            (purposeHome system "test-gnome").config.home.packages;
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
