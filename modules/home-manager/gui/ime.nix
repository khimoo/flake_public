{ config, pkgs, lib, ... }:

lib.mkIf config.local.profile.features.ime {
  i18n.inputMethod = {
    type = "fcitx5";
    enable = true;
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      fcitx5-gtk
      fcitx5-skk
    ];
  };
}
