{ settings, pkgs, lib, ... }:

{
  imports = [
    ./wezterm.nix
  ];

  config = lib.mkIf settings.features.gui {
    home.packages = with pkgs; [
      ipafont
      ipaexfont
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];

    fonts.fontconfig = { enable = true; };

    programs.obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [
        input-overlay
      ];
    };

    programs.foliate.enable = true;
    programs.anki = {
      enable = true;
      language = "ja_JP";
    };
  };
}
