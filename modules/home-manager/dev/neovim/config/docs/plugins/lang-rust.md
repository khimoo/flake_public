# Rust 言語サポート

Rust 専用の LSP 拡張とデバッグ、所有権可視化。

- 設定ファイル: `lua/features/rust.lua`, `lua/features/rustowl.lua`, `lua/plugins/lang/rustowl-hover.lua`

## プラグイン

### rustaceanvim

rust-analyzer の拡張機能を Neovim で使えるようにする。標準の lspconfig ではなく独自に LSP を管理。

主な追加コマンド:
- `:RustLsp debuggables` — デバッグ対象の選択・実行
- `:RustLsp runnables` — 実行対象の選択・実行
- `:RustLsp expandMacro` — マクロ展開の表示
- `:RustLsp explainError` — エラーの詳細説明
- `:RustLsp joinLines` — 行の結合 (Rust 構文を考慮)

デバッグには codelldb を使う。パスは `features.nix` の `rust.data.codelldb` から渡す。

### rustowl

Rust の所有権・ライフタイムをコード上に可視化する。

| キー | 機能 |
|------|------|
| `<leader>lo` | RustOwl の表示 ON/OFF トグル |

- `auto_attach = true`: Rust ファイルを開くと自動で LSP 接続
- `auto_enable = false`: 表示は手動でトグル
- `idle_time = 500`: 500ms 停止後にハイライト更新

#### マウスホバー (rustowl-hover.lua)

RustOwl が有効な状態でマウスをハイライト上に移動すると、所有権の詳細情報がフロートウィンドウに表示される。

- `mousemoveevent = true` を設定して `<MouseMove>` イベントを捕捉
- カーソル移動時にキャッシュをクリアして最新のデコレーションを取得

## プラットフォームとRustOwlの導入

RustOwl は `local.rustowl.enable` で入れる（x86_64 Linux で既定 true、Darwin では false）。サーバーとプラグインはどちらも Nix の store から絶対パスで渡すので、PATH にある別の rustowl は使わない。無効なときはプラグインと対応するキーを読み込まない（[RustOwl の設計](../../../../../../../docs/architecture/rustowl.md)）。
