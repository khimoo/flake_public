# DAP (Debug Adapter Protocol)

Neovim 内でデバッグ実行。ブレークポイント、ステップ実行、変数ウォッチ。

- 設定ファイル: `lua/plugins/dap/init.lua`, `lua/plugins/dap/view.lua`, `lua/config/dap/python.lua`

## プラグイン

### nvim-dap

デバッグアダプタープロトコルのクライアント本体。

### nvim-dap-virtual-text

デバッグ中に変数の値をコード上にインライン表示する。

### nvim-dap-view

デバッグ UI。ウォッチ、スコープ、ブレークポイント、REPL 等をサイドパネルに表示。
デバッグ開始時に自動で開く (`event_initialized` リスナー)。

### nvim-dap-go

Go 用のデバッグアダプター設定 (delve)。`opts = {}` でデフォルト設定。

## キーバインド

全て `<leader>d` 配下。

| キー | 機能 | 説明 |
|------|------|------|
| `<leader>dc` | Continue | デバッグ開始 / 一時停止から再開 |
| `<leader>db` | Toggle breakpoint | ブレークポイントの設置/解除 |
| `<leader>do` | Step over | 次の行へ (関数の中には入らない) |
| `<leader>di` | Step into | 関数の中に入る |
| `<leader>dO` | Step out | 現在の関数から出る |
| `<leader>dr` | REPL | REPL (Read-Eval-Print Loop) を開く |

## dap-view のパネル

winbar のタブで以下のセクションを切り替えられる:

- **watches**: 式のウォッチ
- **scopes**: ローカル変数一覧
- **exceptions**: 例外設定
- **breakpoints**: ブレークポイント一覧
- **threads**: スレッド一覧
- **repl**: REPL
- **console**: デバッグ出力

winbar にはコントロールボタンもある (play, step_into, step_over 等)。

## Rust のデバッグ

rustaceanvim 経由で codelldb を使う。dap-view の winbar に Rust 専用の debug ボタンがあり、`:RustLsp debuggables` を実行する。詳細は [lang-rust.md](./lang-rust.md) を参照。

## 典型的なフロー

```
<leader>db  → ブレークポイントを設置
<leader>dc  → デバッグ開始 (dap-view が自動で開く)
<leader>do  → ステップオーバーで実行を追う
<leader>di  → 気になる関数にステップイン
<leader>dO  → ステップアウトで戻る
<leader>dc  → 続行
```
