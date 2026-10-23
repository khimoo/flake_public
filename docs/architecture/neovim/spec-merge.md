# 言語ごとの設定を spec のマージで足す

使い方: [LSP のサーバーの追加](../../howtouse/neovim/lsp.md#サーバーの追加)、[Treesitter](../../howtouse/neovim/treesitter.md)
実装: [lua/plugins/lang/](../../../modules/home-manager/dev/neovim/config/lua/plugins/lang/)

Markdown や Typst のような言語ごとの設定は、`lua/plugins/lang/<言語>/` に集める。言語の設定には、言語専用のプラグインのほかに、nvim-treesitter に足すパーサーや、nvim-lspconfig に足すサーバーの設定も含まれる。
これらは、共通のプラグインと同じ名前の spec を言語のディレクトリに書き、lazy.nvim の spec のマージで共通の spec の `opts` に足す。共通の spec は言語を知らず、言語を足すときは `lang/<言語>/` を作るだけで済む。

## 今使っている箇所

| 共通の spec | 言語の spec | 足すもの |
|------------|------------|---------|
| `features/treesitter.lua`（nvim-treesitter） | `lang/markdown/treesitter.lua`、`lang/typst/treesitter.lua` | `opts.ensure_installed` にパーサーを足す |
| `features/lsp.lua`（nvim-lspconfig） | `lang/typst/lsp.lua` | `opts.servers.tinymist` に設定と `on_attach` を足す |

`on_attach` のような関数も `opts` のマージで渡るので、サーバーに固有の autocmd も言語のディレクトリに置ける。
言語の spec には `optional = true` を付け、treesitter や lsp の機能を外すと一緒に外れるようにする。

## 一覧は関数の形の opts で足す

lazy.nvim は、表の形の `opts` の配列をマージせず、上書きする。そのため、一覧に足す側は `opts = function(_, opts) vim.list_extend(...) end` の形にする。
共通の spec も関数の形にし、一覧がまだないときだけ空の一覧で初期化する。共通の spec を `opts = { ensure_installed = {} }` にしていたとき、言語の spec が先に処理されると、足した一覧が空で上書きされ、latex のパーサーが入らずに数式が表示されなかった。
lazy.nvim 2025-11-06 の `lua/lazy/core/plugin.lua` の `values` と `_values` で、どちらの順で読んでも一覧が残ることを確かめた。[回帰チェック](../../../scripts/check-neovim-parser-merge.lua) が、実際の lazy.nvim のマージで両方の順を確かめる（[検証ガイド](../../howtouse/validation.md)）。

## 代償

- サーバーの最終的な設定を知るには、関係する spec を探して、マージの結果を頭の中で組み立てる必要がある。
- spec のマージは lazy.nvim の機能なので、プラグインマネージャーを替えるときは、この構成も作り直す。

## 採用しなかった案

- ファイルを分けるだけにする: パーサーやサーバーの設定は共通の spec に書くことになり、言語の設定が複数の場所に散らばる。
- 言語ごとの設定を集める登録の仕組みを作る（LazyVim の extras に近い形）: 個人の設定の規模では仕組みのほうが大きく、どの設定がどこから来たかも追いにくくなる。

参考: [lazy.nvim の Spec Merging](https://lazy.folke.io/spec#%EF%B8%8F-spec-merging)
