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
  use_uv-contracts =
    (lib.lazyDerivation {
      derivation = (
        # uv は use_uv を選んだ利用者にだけ入る。
        assert !home.config.programs.uv.enable;
        pkgs.runCommand "use_uv-contracts" { } ''
          echo "use_uv contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [ "use_uv" ];
    };
}
