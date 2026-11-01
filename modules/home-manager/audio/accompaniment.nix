# 伴奏の自動生成

{ config, pkgs, lib, ... }:

lib.mkIf config.local.profile.features.audio {
  home.packages = [
    (pkgs.callPackage ../../../packages/jjazzlab { })
  ];
}
