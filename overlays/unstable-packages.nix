# 安定チャンネル(nixos-25.11)の版が古すぎて実害が出るパッケージだけを
# nixos-unstable から差し替える overlay。
#
# 採用基準: そのツールが外部サービスのクライアントであり、サーバ側の変更に
# 追随できないと機能欠落ではなく動作不能に転ぶもの。ローカル完結のツールが
# 多少古いのは許容するので、ここには入れない。
#
# 利用側 (modules/home-manager/dev/apps.nix 等) は `pkgs.codex` と書くだけでよく、
# どのチャンネル由来かを知る必要がない。
#
# 現在の対象:
#   codex — OpenAI のコーディングエージェント CLI。25.11 は 0.92.0 で、上流の
#           0.146.0 (2026-07) から約8ヶ月遅れ。認証・モデル選択を OpenAI の
#           サーバとやりとりするため、この乖離は動作不能のリスクになる。
inputs: final: prev: {
  codex = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.codex;
}
