{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) home hasLauncher;
in
{
  cargo_remote_run-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert !(hasLauncher home.config "cargo-remote-run");
        pkgs.runCommand "cargo_remote_run-contracts" { } ''
          echo "cargo_remote_run contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [ "cargo_remote_run" ];
    };

  cargo-remote-run =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommandCC "cargo-remote-run"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.cargo
              pkgs.rustc
              pkgs.rsync
            ];
          }
          ''
            python ${../cargo-remote-run.py} ${../../modules/home-manager/dev/cargo-remote-run.sh}
            touch "$out"
          ''
      );
    })
    // {
      elements = [ "cargo_remote_run" ];
    };
}
