{ skk-dict, settings, config, pkgs, lib, cursor, ... }:
{
  nixpkgs.config.allowUnfree = true;
  home.packages = with pkgs; [
    prismlauncher
    wine64
  ];
}
