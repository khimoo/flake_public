# Markdown

装飾、数式の近似表示、箇条書きの入力補助、ブラウザの枠なしウィンドウによるライブプレビュー（画像・Mermaid・KaTeX 数式）を備えた環境で Markdown を編集する。

設定: `lua/plugins/lang/markdown/`、`lua/features/render_markdown.lua`、`lua/config/preview_browser.lua`

Markdown ファイルを開くと、長い行は自動で折り返して表示され、スペルチェックが有効になる（日本語は誤りとして扱われない）。

## 装飾と数式（render-markdown.nvim）

ノーマルモードでは見出しや表を装飾して表示し、インサートモード中やカーソルがある行では元の Markdown を表示する。

| コマンド | 操作 |
|---------|------|
| `:RenderMarkdown toggle` | 装飾の表示を切り替える |
| `:RenderMarkdown enable` / `disable` | 装飾の表示を有効化 / 無効化する |

`$...$` や `$$...$$` の数式は、Unicode 文字を使って近似表示する（例: `$x^2 + y^2 = r^2$` は `x² + y² = r²`）。ただし、行列や複雑な分数は粗い表示になる。
`\(...\)` や `\[...\]` の記法には対応していないため、`$` で記述する。

数式が表示されない場合は、LaTeX パーサーが入っているかを確認する。`:RenderMarkdown debug` を実行して数式の行で "no marks on row" と出力されるなら、パーサーが存在しない。パーサーは初回の起動時に自動でコンパイルされるため、完了後に Markdown ファイルを開き直す。

## 箇条書き（autolist.nvim）

| キー | モード | 動作 |
|------|--------|------|
| `<CR>` | i | 同じ階層で次の項目を作成する |
| `<Tab>` | i | 項目を 1 段深くする（インデント） |
| `<S-Tab>` | i | 項目を 1 段浅くする（逆インデント） |
| `o` / `O` | n | 下 / 上の行に項目を作成する |

番号付きリストは、階層を変更すると番号が自動で振り直される。
Markdown バッファでは、スニペットの展開中であっても `<Tab>` が箇条書きの操作になるため、blink.cmp のプレースホルダー移動には使用できない。

SKK が有効なときも、改行すると次の項目が作成される。変換を確定する `<CR>` では改行されないため、項目は作成されない（詳細は [skkeleton.md](./skkeleton.md) を参照）。

## プレビューする（mdkite.nvim）

画像・Mermaid 図・数式を含めて確認したいときは、`:MarkdownPreview` を実行する。固定ポート `127.0.0.1:8421` の `takeover` モードでローカルサーバを起動し、拡張機能の無い Google Chrome（無ければ Brave）の `--app` モードで枠なしウィンドウを 1 枚開く。

- 別の Markdown ファイルへ切り替えたときは、`:MdKite start` で既存の 1 窓の中身をそのまま切り替えられる。
- ブラウザ側には Neovim のカーソル・スクロールが追従し、Mermaid 図のズームやパン、KaTeX 数式、ローカル画像が表示される。

| コマンド | 動作 |
|---------|------|
| `:MarkdownPreview` | サーバを起動し、枠なしブラウザ窓（`http://127.0.0.1:8421`）を開く |
| `:MdKite start` | サーバを起動（既存窓がある場合はそのまま対象ファイルを切り替え） |
| `:MdKite stop` | サーバを停止する |
| `:MdKite refresh` | プレビューを手動で再描画する |

## 見出しとリンク（marksman）

marksman（LSP）が見出しを Document Symbol として抽出し（`<leader>fs` で一覧表示可能）、`[[...]]` のリンクを補完してリンク切れを診断する。`gd` や `grr` などのキーバインドは [lsp.md](./lsp.md) と共通。

## 設計

編集中の軽い装飾は `render-markdown.nvim`（数式は `latex2text` による Unicode 近似表示）で済ませ、画像・Mermaid・複雑な数式の確認は端末プロトコル依存のインライン描画ではなく、Niri の隣の列に並べる枠なしブラウザ窓（`mdkite.nvim` + `preview_browser.lua`）へ分離した。これにより、`ng`・kitty・WSL のどれから編集しても同じ見た目で確認でき、`mmdc`（Chromium）や ImageMagick といった重い外部依存も不要になる。

`render-markdown.nvim` は LaTeX パーサーを使って数式を検出するため、LaTeX パーサーが必須となる。このパーサーは文法定義（grammar）から生成・コンパイルされるため、`tree-sitter` の CLI と Node.js も必要になる。

`--app` 窓のブラウザは、拡張機能を入れていない素の Google Chrome を優先し、無ければ Brave、どちらも無い環境（WSL 等）では Neovim 標準の `vim.ui.open` にフォールバックする（[preview_browser.lua](../../../modules/home-manager/dev/neovim/config/lua/config/preview_browser.lua)）。
