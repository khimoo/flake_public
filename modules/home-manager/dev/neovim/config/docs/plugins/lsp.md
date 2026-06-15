# LSP (Language Server Protocol)

コードの定義ジャンプ、補完、診断、リネーム等を提供する。

- 設定ファイル: `lua/plugins/lsp/init.lua`, `lua/config/lsp/keymaps.lua`, `lua/config/lsp/diagnostics.lua`
- 依存: nvim-lspconfig, blink.cmp

## サーバーの設定方法

### サーバー一覧 (どの LSP を有効化するか)

`modules/home-manager/dev/lsp.nix` の `lspServers` に nixpkgs パッケージと LSP 識別子のペアを書く。Nix が `~/.local/share/nvim/nix/lsp-servers.lua` に識別子の Lua 配列を生成し、`plugins/lsp/init.lua` が `dofile` で読み込んでループ有効化する。

新しい LSP を追加する手順:
1. `dev/lsp.nix` の `lspServers` に `{ pkg = pkgs.foo; lsp = "foo_ls"; }` を追加
2. rebuild
3. 自動で `vim.lsp.enable("foo_ls")` まで走る

この設計の利点: LSP サーバーバイナリの導入 (`home.packages`) と nvim 側での有効化が **同じリストの 1 行から両方派生する** ので、片方を書き忘れない。

### サーバー固有の設定 (capabilities 以外の override)

`plugins/lsp/init.lua` の `opts.servers` テーブルで設定する。例:

```lua
opts = {
  servers = {
    tinymist = {
      settings = { exportPdf = "onType", outputPath = "/tmp/tinymist" },
    },
    nil_ls = {
      settings = { ['nil'] = { formatting = { command = { "nixfmt" } } } },
    },
  },
},
```

このテーブルは **lazy.nvim の spec マージで言語モジュールから拡張可能**。例えば `lang/markdown/lsp.lua` で `opts.servers.marksman = { ... }` を返す spec を書けば、`nvim-lspconfig` の opts に deep-merge される。詳細は [架構ドキュメント (spec マージ)](../architecture/spec-merge.md) を参照。

現状の override:
- `tinymist`: Typst 用。`exportPdf = "onType"` でリアルタイム PDF 出力
- `nil_ls`: Nix 用。`nixfmt` でフォーマット

## キーバインド

### プレフィックスなし (頻出操作)

LSP がアタッチされたバッファでのみ有効。

| キー | 機能 | 説明 |
|------|------|------|
| `gd` | 定義にジャンプ | **最も使う**。関数・型の定義元に飛ぶ |
| `gD` | 宣言にジャンプ | C 言語等のヘッダ宣言に飛ぶ |
| `gi` | 実装にジャンプ | インターフェースの実装に飛ぶ |
| `grr` | 参照一覧 | シンボルが使われている箇所を一覧表示 |
| `grn` | リネーム | プロジェクト全体でシンボルを一括リネーム |
| `gra` | コードアクション | 自動修正候補の表示・適用 |
| `gri` | 実装一覧 | インターフェースの実装を一覧表示 |
| `K` | ホバー | カーソル下の型情報・ドキュメントを表示 |
| `<C-s>` | シグネチャヘルプ | 関数の引数情報を表示 |
| `[d` | 前の診断 | 前のエラー/警告にジャンプ |
| `]d` | 次の診断 | 次のエラー/警告にジャンプ |

> 注: `gr*` 系は Neovim 0.11+ のデフォルトマッピング。設定ファイルでの定義は不要。

### `<leader>l` プレフィックス付き (低頻度操作)

| キー | 機能 | 説明 |
|------|------|------|
| `<leader>lrn` | リネーム | プロジェクト全体でシンボルを一括リネーム |
| `<leader>lca` | コードアクション | 自動修正候補の表示・適用 |
| `<leader>lF` | フォーマット | バッファ全体をフォーマット (非同期) |
| `<leader>lD` | 型定義にジャンプ | |
| `<leader>ldl` | 診断フロート | カーソル位置の診断詳細をフロート表示 |
| `<leader>lwa` | ワークスペース追加 | |
| `<leader>lwr` | ワークスペース削除 | |
| `<leader>lwl` | ワークスペース一覧 | |

ビジュアルモード:
| キー | 機能 |
|------|------|
| `<leader>lca` | 選択範囲のコードアクション |

## 診断の設定

- `virtual_text = false`: 行末のインライン診断テキストは非表示
- `signs = true`: 行番号横にアイコン表示
- `update_in_insert = true`: 挿入モード中もリアルタイム更新
- `CursorHold` で自動的に診断フロートを表示 (250ms 停止後)

## ナビゲーションのコツ

- `gd` → `<C-o>` で戻る → `gd` → `<C-o>` のループがコードリーディングの基本
- `<C-o>` は何回でも遡れる。逆方向は `<C-i>`
- `grr` と `<leader>fr` (Telescope 版) は同じ機能。Telescope 版のほうがプレビュー付き
