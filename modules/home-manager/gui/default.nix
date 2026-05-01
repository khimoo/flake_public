{ settings, config, pkgs, lib, ... }:

let
  terminalFont = {
    package = pkgs.plemoljp-nf;
    name = "PlemolJP Console NF";
  };

in lib.mkIf settings.features.gui {
  home.packages = with pkgs; [
    wezterm
    thunderbird
    slack
    zoom-us
    yt-dlp
    transcribe
    appimage-run
    krita
    tdf
    typst
    libreoffice
    pdfarranger
    obsidian
    bitwarden-desktop
    teams-for-linux
    vmpk
    vlc
    obs-studio
    xournalpp
    google-chrome

    ipafont
    ipaexfont
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    terminalFont.package
  ];

  fonts.fontconfig = { enable = true; };

  programs.foliate.enable = true;
  programs.anki = {
    enable = true;
    language = "ja_JP";
  };

  # mkOutOfStoreSymlinkを使えばrebuild不要で即反映できるが、絶対パスのハードコードが必要になるため使用しない
  xdg.configFile."wezterm/wezterm.lua".source = ../../../dotfiles/wezterm/wezterm.lua;
  xdg.configFile."wezterm/font.lua".text = ''return "${terminalFont.name}"'';

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "firefox.desktop";
      "text/xml" = "firefox.desktop";
      "application/xhtml+xml" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
    };
  };
}
