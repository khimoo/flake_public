# 安定（stable）チャンネル（nixos-25.11）のバージョンが古すぎることで、実際の運用に支障が出る
# パッケージのみを nixos-unstable のものに差し替えるための overlay です。
#
# 採用基準：安定チャンネルのバージョンのままだと機能が正常に動作せず、かつ unstable 側でその問題が
# 解決されていること。単に新しいバージョンの方が好ましいという理由だけでは追加しません。
#
# 各パッケージの採用根拠や差し替えを除外する条件については、
# docs/architecture/unstable-packages.md に記載されています。
#
# 利用側（modules/home-manager/dev/apps.nix など）は `pkgs.tinymist` のように指定するだけでよく、
# そのパッケージがどのチャンネルから取得されたかを意識する必要はありません。
inputs: final: prev:
let
  # legacyPackages は config を持たない素の nixpkgs なので、そのまま参照すると
  # 差し替えた側だけ allowUnfree が効かず claude-code の評価が止まる。
  # 安定チャンネル側の config を引き継いで読み直す。
  unstable = import inputs.nixpkgs-unstable {
    inherit (prev.stdenv.hostPlatform) system;
    inherit (prev) config;
  };
in
{
  inherit (unstable)
    tinymist
    neovim-unwrapped
    tree-sitter
    claude-code
    graphify
    ;
}
