{ settings, terminalFont, config, pkgs, lib, ... }:

lib.mkIf settings.features.gui {
  home.packages = [ pkgs.wezterm ];

  # wezterm.lua は mkOutOfStoreSymlink でリポジトリへの symlink にする。
  # ディレクトリではなくファイル単位の symlink なので、同じ ~/.config/wezterm/ 配下に
  # 後段の font.lua (bridge file) を共存できる (nvim の bridge file 引っ越し問題は発生しない)。
  xdg.configFile."wezterm/wezterm.lua".source =
    config.lib.file.mkOutOfStoreSymlink
      "${settings.flakeRoot}/modules/home-manager/gui/wezterm/wezterm.lua";

  # 参照元: modules/home-manager/gui/wezterm/wezterm.lua
  xdg.configFile."wezterm/font.lua".text = ''return "${terminalFont.name}"'';
}
