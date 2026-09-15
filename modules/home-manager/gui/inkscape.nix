{ config, pkgs, lib, ... }:

lib.mkIf config.local.profile.features.gui {
  home.packages = [ pkgs.inkscape ];

  # 新規文書の既定テンプレート（ページとデスクの色）。mkOutOfStoreSymlink でリポジトリへの
  # symlink にするので、GUI の「テンプレートを保存...」→「デフォルトテンプレートとして設定」が
  # リポジトリのファイルを直接書き換える。GUI から保存すると表示倍率やウィンドウ寸法も
  # 書き込まれるので、コミット前に差分を確かめる。
  # 参照元: docs/howtouse/inkscape.md, docs/architecture/inkscape.md
  xdg.configFile."inkscape/templates/default.svg".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.local.profile.flakeRoot}/modules/home-manager/gui/inkscape/default.svg";
}
