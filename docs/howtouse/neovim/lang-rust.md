# Rust

rustaceanvim が rust-analyzer を管理し、RustOwl が所有権とライフタイムをコード上に可視化する。cargo および rust-analyzer は各プロジェクトの devShell で提供されるものを利用する。

設定: `lua/features/rust.lua`、`lua/features/rustowl.lua`、`lua/plugins/lang/rustowl-hover.lua`

## rustaceanvim のコマンド

| コマンド | 機能 |
|----------|------|
| `:RustLsp runnables` | 実行可能なターゲットを選択して実行する |
| `:RustLsp debuggables` | デバッグ可能なターゲットを選択してデバッグ実行する |
| `:RustLsp expandMacro` | マクロを展開して表示する |
| `:RustLsp explainError` | エラーの詳細な解説を表示する |
| `:RustLsp joinLines` | Rust の構文規則に合わせて行を結合する |

デバッグ機能には codelldb を使用する（詳細は [dap.md](./dap.md) を参照）。

## 所有権・ライフタイムの可視化（RustOwl）

| キー | 機能 |
|------|------|
| `<leader>lo` | RustOwl の表示 / 非表示を切り替える |

Rust ファイルを開くと自動的に RustOwl サーバーへ接続されるが、コード上の表示は `<leader>lo` で有効化するまで表示されない。有効化している間は、カーソルの動きを 500ms 静止すると表示が自動更新される。ハイライト部分にマウスカーソルを合わせると、詳細情報がフロートウィンドウで表示される。

RustOwl は `local.rustowl.enable` オプションで有効化できる。x86_64 Linux ではデフォルトで有効、それ以外の環境では無効になっており、無効時はプラグイン本体や `<leader>lo` のキーマッピング自体が読み込まれない。詳細な仕組みについては [RustOwl の設計](../../architecture/rustowl.md) を参照。
