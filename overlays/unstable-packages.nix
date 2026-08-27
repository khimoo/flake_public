# 安定チャンネル(nixos-25.11)の版が古すぎて実害が出るパッケージだけを
# nixos-unstable から差し替える overlay。
#
# 採用基準: 安定チャンネルの版のままだと機能が動作不能になり、かつ unstable 側で
# 解決済みであること。単に新しい方が嬉しいだけのものは入れない。
#
# 利用側 (modules/home-manager/dev/apps.nix 等) は `pkgs.codex` と書くだけでよく、
# どのチャンネル由来かを知る必要がない。
#
# 現在の対象:
#   codex — OpenAI のコーディングエージェント CLI。25.11 は 0.92.0 で、上流の
#           0.146.0 (2026-07) から約8ヶ月遅れ。認証・モデル選択を OpenAI の
#           サーバとやりとりするため、この乖離は動作不能のリスクになる。
#   tinymist — Typst の LSP 兼プレビュー。25.11 の 0.14.2 は preview の
#              ビューポート計算を誤り、partial rendering 時に表示外のページが
#              canvas で描画されて span 情報が失われる。結果ページ3付近から
#              プレビューのクリックでエディタへジャンプできない
#              (Myriad-Dreamin/tinymist#2267、#2269 で修正)。unstable は 0.15.2。
inputs: final: prev: {
  codex = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.codex;
  tinymist = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.tinymist;
}
