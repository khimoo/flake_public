# Antigravity CLI の導入

[howtouse/cli-tools/antigravity-cli.md](../howtouse/cli-tools/antigravity-cli.md) の設計判断。

## 使いみち

agents-private の gemini-proofread スキルは、日本語の校正を Gemini の API（無料枠）に送る。
API が失敗したとき（429、5xx、タイムアウトなど）と、人が Gemini 3.8 を指定したときに、`agy -p` で同じ内容を `gemini-3.8-flash` に送る。
Antigravity の枠は API の無料枠とは別で、Google アカウントに紐づく。Google AI の Pro と Ultra 以外は週ごとの枠になる。
2026-09-25 の計測では、約5800字の文書1本の校正で、週の枠の約 2.75% を使った。

## 版を固定して autoPatchelf で包む

配布物は glibc に動的リンクした単体バイナリで、nixpkgs には無い（`nixpkgs#antigravity` は IDE のほう）。
NixOS では nix-ld なしに起動できないので、`autoPatchelfHook` でローダーのパスを書き換える。必要なライブラリは glibc だけ（1.2.10 で `ldd` を確認）。
版は公式マニフェストの URL と sha512 で固定する。agy の自己更新は Nix store に書き込めず働かないので、版は手で上げる。
Nix store から起動しても、自己更新に妨げられずに校正は最後まで動いた（1.2.10、2026-09-25 に確認）。

退けた案:

- nix-ld を有効にし、公式のインストーラ（`install.sh`）で入れる。自己更新は働くが、宣言的な管理の外でバイナリが書き換わる。nix-ld は agy 以外の配布バイナリも動くようにしてしまう。
- Nix の glibc のローダーから直接起動するラッパーを配る。システムの設定は変えずに済むが、自己更新のときにローダー経由で壊れないかを確かめられていない。

## 未確定

- 固定した古い版がサーバー側で拒まれるようになるか。拒まれるなら、版を上げる頻度を決める。
