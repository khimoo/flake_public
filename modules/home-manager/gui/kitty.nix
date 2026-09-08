{ settings, terminalFont, config, pkgs, lib, ... }:

let
  # smart-splits.nvim の kitty backend が kitty @ kitten で呼ぶスクリプト。plugin 同梱の
  # install-kittens.bash は ~/.config/kitty/ へ命令的にコピーする作りだが、nixpkgs の
  # vimPlugins が同じファイルを持っているので宣言的に置ける。
  smartSplitsKittens = "${pkgs.vimPlugins.smart-splits-nvim}/kitty";
in
lib.mkIf settings.features.gui {
  home.packages = [ pkgs.kitty ];

  # kitty.conf は mkOutOfStoreSymlink でリポジトリへの symlink にする。ディレクトリでは
  # なくファイル単位なので、同じ ~/.config/kitty/ 配下に font.conf と kitten を共存できる。
  xdg.configFile."kitty/kitty.conf".source =
    config.lib.file.mkOutOfStoreSymlink
      "${settings.flakeRoot}/modules/home-manager/gui/kitty/kitty.conf";

  # 参照元: modules/home-manager/gui/kitty/kitty.conf の include
  xdg.configFile."kitty/font.conf".text = ''
    font_family ${terminalFont.name}
  '';

  # 参照元: modules/home-manager/gui/kitty/kitty.conf の neighboring_window / relative_resize
  xdg.configFile."kitty/neighboring_window.py".source =
    "${smartSplitsKittens}/neighboring_window.py";
  xdg.configFile."kitty/relative_resize.py".source =
    "${smartSplitsKittens}/relative_resize.py";
  xdg.configFile."kitty/split_window.py".source =
    "${smartSplitsKittens}/split_window.py";
}
