{ settings, config, pkgs, lib, ... }:

let
  gnomeExtensionsList = with pkgs.gnomeExtensions; [
    clipboard-history
    extension-list
    kimpanel
    gsconnect
    paperwm
    panel-note
  ];

in {
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
    nerd-fonts.fira-code
  ] ++ gnomeExtensionsList;

  fonts.fontconfig = { enable = true; };

  programs.foliate.enable = true;
  programs.anki = {
    enable = true;
    language = "ja_JP";
  };

  xdg.configFile."wezterm/wezterm.lua".source = ../../dotfiles/wezterm/wezterm.lua;

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

  i18n.inputMethod = {
    type = "fcitx5";
    enable = true;
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      fcitx5-gtk
      fcitx5-skk
    ];
  };

  dconf = {
    enable = true;
    settings = {
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = map (ext: ext.extensionUuid) gnomeExtensionsList;
      };
      "org/gnome/desktop/interface" = {
        accent-color = "blue";
        color-scheme = "prefer-dark";
        show-battery-percentage = true;
        toolkit-accessibility = false;
      };
    };
  };

  systemd.user.sessionVariables.NIXOS_OZONE_WL = "1";
}
