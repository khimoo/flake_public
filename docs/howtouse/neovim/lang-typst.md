# Typst

tinymist（LSP）による補完・診断・PDF 出力と、typst-preview.nvim によるブラウザプレビューを提供する。

設定: `lua/plugins/lang/typst/`、`lua/features/typst_preview.lua`

## プレビューする

| 用途 | 手段 | 反映 | カーソルの同期 |
|------|------|------|-------------|
| 普段 | `tdf report.pdf` を別のペインで開く | tinymist が入力のたびに PDF を再生成し、tdf が再読み込みする | なし |
| 位置合わせ、図の調整 | `:TypstPreview` | 差分のみを再描画して入力に追従する | 双方向（プレビューをクリックすると該当行へ移動） |

`tdf` はターミナル内で PDF を表示するビューア（[tdf](../cli-tools/shell-tools.md#tdf)）。
PDF は `report.typ` と同じディレクトリに `report.pdf` として出力される。PDF をリポジトリの管理下に置きたくない場合は、`.gitignore` で除外する。

| コマンド | 動作 |
|----------|------|
| `:TypstPreview` | ブラウザでプレビューを開く |
| `:TypstPreviewToggle` | プレビューの開始 / 停止を切り替える |
| `:TypstPreviewStop` | プレビューを停止する |
| `:TypstPreviewFollowCursorToggle` | カーソル追従のオン / オフを切り替える |
| `:TypstPreviewSyncCursor` | プレビューの表示位置を現在のカーソル位置に同期する |

`:TypstPreviewUpdate` は使用しない。このコマンドを実行すると tinymist と websocat が Nix store の外部にダウンロードされてしまうため、nixpkgs 版を使うように設定して無効化している。

## spin713 から desktop の文書をプレビューする

desktop で編集している文書を、spin713 のブラウザでプレビューできる。

1. spin713 で `ssh desktop-preview` を実行して desktop に入る。この接続名は desktop のポート 23625 を spin713 の同じポートへ転送する。
2. desktop の nvim で `:TypstPreview` を実行する。ssh で入った nvim では、プレビューはポート 23625 で起動し、desktop 側のブラウザは開かない。
3. spin713 のブラウザで `http://127.0.0.1:23625` を開く。

ssh で入ったかどうかは、nvim の環境変数 `SSH_CONNECTION` で判定する。
ポートは 1 つに固定しているので、ssh で入った nvim から同時に開けるプレビューは 1 つだけ。`desktop-preview` の接続を 2 本開くと、2 本目はポートの転送に失敗する（ssh 自体はつながる）。

## 分割した文書を編集する

`#include` されている子ファイルを開いている場合でも、診断やプレビューは文書全体の起点となるファイルからコンパイルされる。
`lua/plugins/lang/typst/main_file.lua` が、現在のファイルを `#include` または `#import` しているファイルを同一ディレクトリ内から検索し、どのファイルからも参照されていない最上位のファイルまで遡って起点として特定する。

```
04-conjecture.typ → report.typ
preamble.typ      → 01-setup.typ → report.typ
solo.typ          → solo.typ（単体文書はそのまま）
```

別の文書のバッファに切り替えると、起点も自動的に切り替わる。
なお、探索対象は同一ディレクトリ内に限られるため、ディレクトリをまたいで `#include` している文書では起点を正しく判定できない。

## 動作が重いとき

tinymist は入力のたびに文書全体をコンパイルして PDF を生成する（`exportPdf = "onType"`）。図が多い文書などで動作が重い場合は、`lua/plugins/lang/typst/lsp.lua` で `"onSave"`（保存時）に変更する。

## 設計

tinymist のデフォルト動作では、現在開いているバッファ自身を起点としてコンパイルする。そのため、`#include` されている子ファイルを開くとメインファイルの `show` ルールが適用されず、他ファイルのラベルへの参照が未解決エラーとして診断に表示されてしまう。
起点のファイル名を設定に固定記述すると文書ごとに書き換える手間が生じるため、`#include` や `#import` の依存関係を遡って起点を自動特定する構成にした。特定した起点は、LSP では `tinymist.pinMain` で固定し、プレビューでは `get_main_file` に渡している。
