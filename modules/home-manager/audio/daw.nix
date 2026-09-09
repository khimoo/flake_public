# DAW ホスト

{ config, pkgs, lib, ... }:

lib.mkIf config.local.profile.features.audio {
  home.packages = with pkgs; [
    zrythm
  ];
}
