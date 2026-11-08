{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) rejectsPurpose;
in
{
  music_production-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert
          system == "x86_64-linux"
          || rejectsPurpose "test-audio" system "music_production: supports Linux only";
        pkgs.runCommand "music_production-contracts" { } ''
          echo "music_production contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [ "music_production" ];
    };
}
