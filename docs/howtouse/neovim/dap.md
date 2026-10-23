# デバッグ（DAP）

nvim-dap を使用してブレークポイントの設定、ステップ実行、変数の確認を行います。デバッグを開始すると nvim-dap-view のパネルが開き、変数の値がコードの横にインライン表示されます。

設定ファイル: `lua/features/dap.lua`（Python: `lua/config/dap/python.lua`、Go: `lua/plugins/lang/go.lua`、Rust: [lang-rust.md](./lang-rust.md)）

## キーマップ

| キー | 機能 |
|------|------|
| `<leader>dc` | デバッグ開始 / 続行 |
| `<leader>db` | ブレークポイントの切り替え（設置 / 解除） |
| `<leader>do` | ステップオーバー（関数内に入らず次へ） |
| `<leader>di` | ステップイン（関数内に入る） |
| `<leader>dO` | ステップアウト（現在の関数を抜ける） |
| `<leader>dr` | REPL を開く |

## パネル操作

dap-view パネル上部のタブで、ウォッチ式（watches）、ローカル変数（scopes）、例外（exceptions）、ブレークポイント（breakpoints）、スレッド（threads）、REPL、デバッグ出力（console）を切り替えられます。タブの横には、続行やステップ実行用のボタンも配置されています。

Rust では、パネル上のボタンから `:RustLsp debuggables` を実行でき、rustaceanvim と codelldb によるデバッグが可能です。

## デバッグの流れ

```
<leader>db  → ブレークポイントを置く
<leader>dc  → デバッグを始める（パネルが開く）
<leader>do  → ステップオーバーで実行を追う
<leader>di  → 気になる関数にステップインする
<leader>dO  → ステップアウトで戻る
<leader>dc  → 続ける
```
