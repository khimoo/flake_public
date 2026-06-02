# trouble.nvim — 診断・quickfix 統合 UI

diagnostics、LSP references、quickfix、loclist、シンボルアウトラインを統一的な UI で表示・操作するプラグイン。

- 設定ファイル: `lua/plugins/trouble.lua`

## キーバインド

### trouble の開閉

| キー | 機能 |
|------|------|
| `<leader>xx` | ワークスペース全体の diagnostics |
| `<leader>xX` | 現在のバッファの diagnostics |
| `<leader>xq` | quickfix リスト |
| `<leader>xl` | location リスト |
| `<leader>xs` | シンボルアウトライン |
| `<leader>xr` | LSP references / definitions |

### trouble ウィンドウ内の操作

| キー | 機能 |
|------|------|
| `<CR>` | 項目を開く |
| `o` | 項目を開く（trouble を閉じない） |
| `j` / `k` | 次/前の項目に移動 |
| `q` | trouble を閉じる |
| `r` | リストを更新 |
| `m` | モードを切り替え |

## Telescope 連携

Telescope の検索結果画面で `<C-t>` を押すと、結果を trouble に送って一覧表示できます。

### 典型フロー: プロジェクト全体の文字列置換

```
<leader>fg          live_grep で検索文字列を入力
<C-t>               検索結果を trouble に送る
                     → trouble に全マッチ箇所が一覧表示される
                     → 各項目を確認しながら修正
```

### 典型フロー: diagnostics を一括処理

```
<leader>xx          ワークスペース全体の diagnostics を表示
                     → ファイルごとにグループ化されて表示
j / k               項目間を移動（プレビュー付き）
<CR>                 修正したい箇所にジャンプ
（修正）
<leader>xx          trouble に戻って次の項目へ
```

### 典型フロー: リファクタリング時の影響確認

```
（カーソルを関数名に合わせて）
<leader>xr          LSP references を trouble に表示
                     → この関数を呼び出している箇所が一覧表示
                     → 各箇所をプレビューで確認しながら修正方針を立てる
```

### 典型フロー: テスト失敗箇所の修正

```
（テスト実行後、quickfix にエラーが入った状態）
<leader>xq          quickfix リストを trouble で表示
                     → 失敗箇所がファイルごとにグループ化
j / k               エラー間を移動しながらプレビューで確認
<CR>                 修正箇所にジャンプ
```

## bqf との違い

- bqf は quickfix ウィンドウの拡張のみ。trouble は diagnostics / references / quickfix / loclist / symbols を同じ UI で扱える
- ファイルごとのツリー表示でグループ化される
- Telescope 連携で検索結果を直接 trouble に送れる

## Telescope との使い分け

| ツール | 用途 |
|--------|------|
| Telescope | **探す** — ファジー検索で1つ選ぶ |
| trouble | **一覧を処理する** — 複数の項目を順番に確認・修正 |

Telescope で検索 → 結果が多い → `<C-t>` で trouble に送る、という流れが基本。
