# 外観・UI プラグイン

ステータスライン、インデントガイド、LSP 進捗、キーバインドヘルプ。

- 設定ファイル: `lua/plugins/lualine.lua`, `lua/plugins/indent.lua`, `lua/plugins/fidget.lua`, `lua/plugins/which-key.lua`

## プラグイン

### lualine.nvim

ステータスライン。テーマは lualine のデフォルト `auto`。現在のカラースキームのハイライトから配色を生成するため、`:set background=light` で切り替えるとステータスラインも追従する。`termguicolors` を自動で ON にする。

設定不要で動作。モード、ファイル名、エンコーディング、行番号等が表示される。

### hlchunk.nvim

現在のスコープ (関数、if ブロック等) をチャンクとしてハイライト表示。
インデントガイドの代替。

- `chunk.enable = true`: 現在のスコープを視覚的に接続線で表示
- `line_num.enable = true`: 現在のスコープの行番号をハイライト

### fidget.nvim

LSP サーバーの処理進捗を右下に小さく表示。フォーマット中、インデックス中等の状態が分かる。

設定不要で動作。

### which-key.nvim

キーバインドのヘルプをポップアップ表示。`<leader>` を押して少し待つと、続けて押せるキーの一覧が表示される。

- プリセット: `modern`
- トリガー: 全モード (`nixsotc`) で `<auto>` 検出

覚えていないキーバインドがあるときは、プレフィックスキーを押して待てば候補が表示される。
