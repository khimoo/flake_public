{ settings, config, pkgs, lib, ... }:

let
  terminalFont = {
    package = pkgs.plemoljp-nf;
    name = "PlemolJP Console NF";
  };

in lib.mkIf settings.features.gui {
  home.packages = with pkgs; [
    wezterm

    ipafont
    ipaexfont
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    terminalFont.package
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

  # mkOutOfStoreSymlinkを使えばrebuild不要で即反映できるが、絶対パスのハードコードが必要になるため使用しない
  # wezterm の背景透過と nvim の背景透過 autocmd を連携させる
  home.sessionVariables.TERMINAL_TRANSPARENT = "1";

  xdg.configFile."wezterm/wezterm.lua".source = ../../../dotfiles/wezterm/wezterm.lua;
  # 参照元: dotfiles/wezterm/wezterm.lua
  xdg.configFile."wezterm/font.lua".text = ''return "${terminalFont.name}"'';

}
