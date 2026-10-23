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

Telescope の検索結果の画面で `<C-t>` を押すと、結果を trouble に送って一覧にできる。

### 検索結果を一つずつ直す

```
<leader>fg          live_grep で検索文字列を入力
<C-t>               検索結果を trouble に送る
                     → trouble に全マッチ箇所が一覧表示される
                     → 各項目を確認しながら修正
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
