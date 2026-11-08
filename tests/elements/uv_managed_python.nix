{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) home;
in
{
  uv_managed_python-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert !(home.config.programs.uv.settings ? python-preference);
        pkgs.runCommand "uv_managed_python-contracts" { } ''
          echo "uv_managed_python contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [ "uv_managed_python" ];
    };
}
