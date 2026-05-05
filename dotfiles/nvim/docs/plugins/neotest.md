# Neotest

テスト実行フレームワーク。カーソル位置のテスト実行、結果表示、DAP 連携デバッグ。

- 設定ファイル: `lua/plugins/neotest.lua`

## プラグイン

### neotest

テストランナーの統合フレームワーク。アダプタ経由で各言語のテストツールと連携する。

### neotest-rust

Rust (`cargo test`) 用アダプタ。テスト名を自動検出し、個別テストの実行が可能。

## キーバインド

全て `<leader>t` 配下。

| キー | 機能 | 説明 |
|------|------|------|
| `<leader>tt` | Run nearest | カーソルに最も近いテストを実行 |
| `<leader>tf` | Run file | 現在のファイルの全テストを実行 |
| `<leader>tl` | Run last | 前回実行したテストを再実行 |
| `<leader>ts` | Toggle summary | テスト一覧サイドパネルの表示/非表示 |
| `<leader>to` | Show output | テスト出力をフロートウィンドウで表示 |
| `<leader>tO` | Toggle output panel | テスト出力パネルの表示/非表示 |
| `<leader>tS` | Stop | 実行中のテストを停止 |
| `<leader>td` | Debug nearest | カーソルに最も近いテストを DAP でデバッグ実行 |

## 典型的なフロー

### テスト駆動開発

```
(テストコードを書く)
<leader>tt  → カーソル下のテストを実行 (失敗する)
(実装を書く)
<leader>tl  → 前回のテストを再実行 (通るまで繰り返し)
<leader>tf  → ファイル全体のテストで回帰確認
```

### テストのデバッグ

```
<leader>db  → テスト内にブレークポイントを設置
<leader>td  → DAP 経由でテストをデバッグ実行 (dap-view が自動で開く)
<leader>do  → ステップオーバーで実行を追う
```

## 注意事項

- Rust の場合、`cargo test` がバックエンドなので初回はコンパイルが走る
- `<leader>td` (デバッグ) には codelldb が必要 (rustaceanvim と同じ設定を共有)
