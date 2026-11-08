{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) ;
in
{
  # mc-setup-hooks が prismlauncher.cfg の [General] だけを書き換え、起動中は触らないこと。
  minecraft-setup-hooks =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "minecraft-setup-hooks"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.gawk
            ];
          }
          ''
            python ${../minecraft-setup-hooks.py} ${../../modules/home-manager/minecraft-setup-hooks.sh}
            touch "$out"
          ''
      );
    })
    // {
      elements = [ "minecraft_backup" ];
    };
}
