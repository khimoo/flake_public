# 安定チャンネル(nixos-25.11)の版が古すぎて実害が出るパッケージだけを
# nixos-unstable から差し替える overlay。
#
# 採用基準: 安定チャンネルの版のままだと機能が動作不能になり、かつ unstable 側で
# 解決済みであること。単に新しい方が嬉しいだけのものは入れない。
#
# 対象ごとの根拠と外す条件は docs/architecture/unstable-packages.md にある。
#
# 利用側 (modules/home-manager/dev/apps.nix 等) は `pkgs.tinymist` と書くだけでよく、
# どのチャンネル由来かを知る必要がない。
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
