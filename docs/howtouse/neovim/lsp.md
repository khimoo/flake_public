# LSP

定義へのジャンプ、参照の一覧表示、リネーム、診断は LSP で行います。なお、Rust は rustaceanvim が個別に管理しています（[lang-rust.md](./lang-rust.md) を参照）。

設定ファイル: `lua/features/lsp.lua`、`lua/config/lsp/keymaps.lua`、`lua/config/lsp/diagnostics.lua`

## サーバーの追加

1. [features.nix](../../../modules/home-manager/dev/neovim/features.nix) の `lspServers` に `{ pkg = pkgs.foo; lsp = "foo_ls"; }` を追加する（`lsp` には nvim-lspconfig のサーバー名を指定）。
2. Home Manager を switch する。

`lspServers` に 1 行追加するだけで、サーバーが Neovim の PATH に追加され、同時に `vim.lsp.enable("foo_ls")` による有効化処理も行われるため、他の箇所を修正する必要はありません。

サーバーごとの個別設定は、`lua/features/lsp.lua` の `opts.servers.<サーバー名>` に記述します。
言語ごとの設定は、各言語のディレクトリから同じ `opts.servers` に追加できます（例: `lua/plugins/lang/typst/lsp.lua` の tinymist）。仕組みの詳細は [spec のマージ](../../architecture/neovim/spec-merge.md) を参照してください。

## キーマップ

LSP が接続されたバッファでのみ利用可能です。`gr` で始まるキーは Neovim の標準キーマップです。

| キー | 機能 |
|------|------|
| `gd` | 定義へ移動 |
| `gD` | 宣言へ移動 |
| `gi` | 実装へ移動 |
| `grr` | 参照の一覧表示 |
| `grn` | リネーム |
| `gra` | コードアクション |
| `gri` | 実装の一覧表示 |
| `K` | ホバー表示（型やドキュメントの確認） |
| `<C-s>` | シグネチャヘルプ（挿入モード） |
| `[d` / `]d` | 前 / 次の診断へ移動 |

使用頻度の低い操作は `<leader>l` 配下に割り当てられています。

| キー | 機能 |
|------|------|
| `<leader>lrn` | リネーム |
| `<leader>lca` | コードアクション（ビジュアルモードでは選択範囲に適用） |
| `<leader>lF` | バッファ全体のフォーマット |
| `<leader>lD` | 型定義へ移動 |
| `<leader>ldl` | カーソル位置の診断をフロート表示 |
| `<leader>lwa` / `<leader>lwr` / `<leader>lwl` | ワークスペースフォルダの追加 / 削除 / 一覧表示 |

## 診断情報の表示

行末には診断メッセージを表示せず、行番号の横にアイコンのみを表示します。カーソルを 250ms 静止させると、その位置の診断情報がフロートウィンドウで表示されます。挿入モード中も診断情報はリアルタイムで更新されます。
