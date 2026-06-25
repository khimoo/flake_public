# DAW ホスト

{ settings, pkgs, lib, ... }:

lib.mkIf settings.features.audio {
  home.packages = with pkgs; [
    zrythm
  ];
}
