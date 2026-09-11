# 安定チャンネル(nixos-25.11)の版が古すぎて実害が出るパッケージだけを
# nixos-unstable から差し替える overlay。
#
# 採用基準: 安定チャンネルの版のままだと機能が動作不能になり、かつ unstable 側で
# 解決済みであること。単に新しい方が嬉しいだけのものは入れない。
#
# 利用側 (modules/home-manager/dev/apps.nix 等) は `pkgs.tinymist` と書くだけでよく、
# どのチャンネル由来かを知る必要がない。
#
# codex はここから外し、専用 flake (codex-cli-nix) から取っている。unstable でも
# 上流リリースへの追従が数週間遅れ、その遅れ自体が動作不能を招くため。flake.nix の
# inputs.codex-cli-nix を参照。
#
# 現在の対象:
#   tinymist — Typst の LSP 兼プレビュー。25.11 の 0.14.2 は preview の
#              ビューポート計算を誤り、partial rendering 時に表示外のページが
#              canvas で描画されて span 情報が失われる。結果ページ3付近から
#              プレビューのクリックでエディタへジャンプできない
#              (Myriad-Dreamin/tinymist#2267、#2269 で修正)。unstable は 0.15.2。
#
#   neovim-unwrapped — kitty の scrollback_pager を Neovim に向ける設定が 25.11 の
#              0.11.7 で成立しない。kitty 推奨行が使う nvim_open_term はチャンネルを
#              開くだけで、stdin から読み込み済みのバッファ内容を端末へ転送しないため
#              画面が空になる (neovim#33720 で修正、0.12 以降)。unstable は 0.12.5。
#              chansend で自分で流し込む回避行なら 0.11.7 でも読めるので、この項目は
#              採用基準を厳密には満たさない。経緯は
#              docs/architecture/unstable-packages.md を参照。
#
#   tree-sitter — nvim-treesitter の main ブランチが全パーサの導入で
#              `tree-sitter build` を呼び、CLI 0.26.1 以上を要求する
#              (main の lua/nvim-treesitter/health.lua の TREE_SITTER_MIN_VER)。
#              25.11 は 0.25.10 で要件を満たさず、パーサを一つも導入できない。
#              unstable は 0.26.11。上の neovim-unwrapped を 0.12 に上げた結果
#              master ブランチが使えなくなったことに連動する項目で、
#              neovim-unwrapped を 25.11 に戻すならこれも不要になる。
#
#   claude-code — 25.11 の 2.1.140 では Claude Fable 5.1 (claude-fable-5-1) を
#              選べない。上流がこのモデルを既定の Fable として追加したのは
#              2.1.257 (CHANGELOG)。/model の一覧も課金の同意もクライアント側の
#              実装に依存するので、古い版のままでは新しいモデルに届かない。
#              unstable は 2.1.263。
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
    ;
}
