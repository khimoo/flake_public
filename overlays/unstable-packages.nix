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
inputs: final: prev: {
  tinymist = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.tinymist;
  neovim-unwrapped = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.neovim-unwrapped;
}
