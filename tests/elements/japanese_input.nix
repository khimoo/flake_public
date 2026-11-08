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
  japanese_input-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert
          system != "x86_64-linux"
          ||
            builtins.any (p: (p.pname or "") == "kitty")
              (purposeHome system "test-ime").config.home.packages;
        pkgs.runCommand "japanese_input-contracts" { } ''
          echo "japanese_input contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "japanese_input"
        "kitty"
      ];
    };
}
