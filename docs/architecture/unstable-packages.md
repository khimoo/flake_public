# nixos-unstable からの部分的な差し替え

設定ファイル: `overlays/unstable-packages.nix`、input は `flake.nix` の `nixpkgs-unstable`

## 問題

この flake は nixpkgs を `nixos-25.11` にピン止めしている。安定チャンネルは分岐後に新機能を取り込まない
ため、更新の速いパッケージほど上流との差が開く。

codex (OpenAI のコーディングエージェント CLI) の場合:

| 取得元 | version |
|--------|---------|
| nixos-25.11 | 0.92.0 |
| nixos-unstable | 0.146.0 |
| 上流 openai/codex の最新リリース | 0.146.0 (2026-07-29) |

同時点の claude-code は 25.11 が 2.1.140、unstable が 2.1.220。

古いままで困るかどうかはパッケージの性格による。ローカルで完結するツールなら機能が少し古いだけで済むが、
codex は認証とモデル選択を OpenAI のサーバとやりとりするクライアントで、サーバ側の変更に追随できないと
機能欠落ではなく動作不能に転びうる。

遅れが動作不能に転ぶ経路はもう一つある。安定チャンネルが取り込んだ版がたまたま既知のバグ持ちで、
上流では修正済みという場合で、tinymist (Typst の LSP 兼プレビュー) がこれに当たった。

| 取得元 | version |
|--------|---------|
| nixos-25.11 | 0.14.2 |
| nixos-unstable | 0.15.2 |

0.14.2 は preview のビューポート計算を誤り、partial rendering を有効にすると表示範囲外のページが
SVG ではなく canvas で描画される。canvas には span 情報が乗らないため、プレビューをクリックしても
エディタへジャンプできない。境界はズーム率次第で、既定の倍率ではおおむね3ページ目から効かなくなる。
上流の [issue #2267](https://github.com/Myriad-Dreamin/tinymist/issues/2267) として報告され、
PR #2269 (2025-11-23) で修正された。0.14.2 のリリースは 2025-11-22 で、この修正の直前に当たる。

## 判断

`nixpkgs-unstable` を input に追加し、overlay で対象パッケージだけを差し替える。全体を unstable に
するのではなく、パッケージ単位の allowlist にする。

- 採用基準は「安定チャンネルの版のままだと機能が動作不能になり、かつ unstable 側で解決済みか」。
  該当する経路は2つで、外部サービスのクライアントがサーバ側の変更に追随できない場合 (codex) と、
  安定チャンネルの版が既知のバグ持ちで上流が修正済みの場合 (tinymist)。動くものが少し古いだけなら
  ここには入れない。
- overlay にしたのは利用側を無関係に保つため。`modules/home-manager/dev/apps.nix` は `codex` と書くだけで、
  どのチャンネル由来かを知らない。取得元を変えても利用側の記述は変わらない。
- overlay は `mkSystem` と `mkHome` の双方に渡っている (`flake.nix` の `overlays`) ので、NixOS ホストと
  standalone home-manager (WSL / macOS) で同じものが入る。
- 既存の `overlays/default.nix` とはファイルを分けた。あちらは上流が直したら消す一時的なパッチの
  置き場で、こちらは安定チャンネルが追いついたら外す差し替えなので、削除の契機が違う。

コストは nixpkgs を 2 つ評価する分の時間とメモリ、および closure に unstable 側の stdenv 由来の依存が
別途乗ること。

全体を unstable に上げる案は見送った。home-manager が `release-25.11` に固定されていて `master` へ
道連れになること、`follows` している小規模な input (winapps / claude-history / zettelkasten) が
nixpkgs の破壊的変更に追随できるか読めないこと、musnix がリアルタイムオーディオでカーネル設定に
踏み込んでいることが理由。2パッケージのために動かす範囲としては大きい。

## 見直しの契機

- NixOS のリリースを上げたとき: 差が縮んでいれば対象から外して安定チャンネルに戻す。tinymist は
  修正を含む 0.15 以降が安定チャンネルに入った時点で外せる。
- 全体を unstable に移行したとき: この overlay と input ごと不要になる。
- 対象を増やすとき: 上の採用基準に照らす。「新しい方が嬉しい」だけでは足さない。

## 関連

- [devshells.md](./devshells.md) — devShell 側も同じ overlay を通る
- [claude-config.md](./claude-config.md) — Claude Code のユーザー設定の管理
