# Typst

tinymist (LSP) と typst-preview.nvim を組み合わせる。
Typst + Neovim の界隈で標準的な構成で、言語機能とプレビューを別プロセスに分ける。

> 設定: `lua/plugins/lang/typst/`
> パッケージ: tinymist は `modules/home-manager/dev/lsp.nix`、websocat は `modules/home-manager/dev/neovim/default.nix`

## プレビューの二系統

| 用途 | 手段 | 反映 | カーソル同期 |
|------|------|------|-------------|
| 普段 | `tdf report.pdf` を別ペインで開く | tinymist が保存/入力ごとに PDF を書き、tdf が hot reload | なし |
| 位置合わせ・図の調整 | `:TypstPreview` | 差分レンダリングで打鍵に追従 | 双方向 (プレビューのクリックで該当行へ) |

`tdf` は端末内に kitty graphics protocol で PDF を描くビューア。
使い方は [tdf のドキュメント](../../../../../../../docs/howtouse/cli-tools/shell-tools.md#tdf) を参照。

PDF の出力先は tinymist の既定 (`$dir/$name`) なので、`report.typ` の隣に `report.pdf` ができる。
`tdf` に渡すパスが自明になるようこうしている。
PDF をリポジトリに置きたくない場合は、対象リポジトリの `.gitignore` で弾く。

## 分割された文書の扱い

tinymist は既定で「開いているバッファ自身」をエントリポイントとして解決する (`projectResolution = "singleFile"`)。
そのため `#include` される側のファイルを開くと、root にある `show` rule が効かず、他ファイルで定義されたラベルへの参照が未解決の診断として出る。

`lang/typst/main_file.lua` がこれを解く。
現在のファイルを `#include` または `#import` しているファイルを同じディレクトリから探し、見つかったらそれを起点にして同じ探索を繰り返す。
誰からも参照されないファイルに行き着いたらそこが起点。

```
04-conjecture.typ → report.typ
preamble.typ      → 01-setup.typ → report.typ
solo.typ          → solo.typ          (単体の文書はそのまま)
```

求めた起点は二箇所で使う。

LSP 側は `on_attach` と `BufEnter` で `tinymist.pinMain` を呼び、コンパイルと診断の起点を固定する。
別の文書のバッファに移ると自動で pin し直すので、手動の操作は要らない。

プレビュー側は `get_main_file` に同じ関数を渡す。

起点をファイル名で設定に書くと文書ごとに書き換えが要るため、この方式にしている。
代わりに、参照関係が同一ディレクトリ内で閉じていることを前提にしている。
ディレクトリをまたいで `#include` する構成では解決できない。

## コマンド

| コマンド | 動作 |
|----------|------|
| `:TypstPreview` | ブラウザでプレビューを開く |
| `:TypstPreviewToggle` | プレビューの開始/停止 |
| `:TypstPreviewStop` | プレビューを停止 |
| `:TypstPreviewFollowCursorToggle` | カーソル追従の切替 |
| `:TypstPreviewSyncCursor` | プレビューを現在のカーソル位置へ飛ばす |

`:TypstPreviewUpdate` は使わない。
このコマンドは tinymist と websocat を Nix store の外にダウンロードするため、`dependencies_bin` で nixpkgs 版を指して無効化してある。

## 負荷が気になるとき

`exportPdf = "onType"` は打鍵のたびに文書全体をコンパイルする。
図が多い文書で重いと感じたら `lang/typst/lsp.lua` で `"onSave"` に変える。
