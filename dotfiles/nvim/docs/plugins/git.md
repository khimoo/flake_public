# Git 連携

変更の可視化、hunk 操作、diff 表示。

- 設定ファイル: `lua/plugins/git.lua`

## プラグイン

### gitsigns.nvim

行番号横に変更状態を表示し、hunk 単位での操作を提供する。

### diffview.nvim

リッチな diff ビューア。`:DiffviewOpen` で使う。

## キーバインド (gitsigns)

全て `<leader>g` 配下。LSP がなくても Git リポジトリ内なら動作する。

### ナビゲーション

| キー | 機能 |
|------|------|
| `]c` | 次の変更箇所 (hunk) にジャンプ |
| `[c` | 前の変更箇所 (hunk) にジャンプ |

diff モード中は Vim 標準の `]c`/`[c` として動作する。

### hunk 操作

| キー | モード | 機能 |
|------|--------|------|
| `<leader>gs` | n | hunk をステージ |
| `<leader>gr` | n | hunk をリセット (変更取消) |
| `<leader>gs` | v | 選択範囲をステージ |
| `<leader>gr` | v | 選択範囲をリセット |
| `<leader>gS` | n | バッファ全体をステージ |
| `<leader>gR` | n | バッファ全体をリセット |

### プレビュー

| キー | 機能 |
|------|------|
| `<leader>gp` | hunk のプレビュー (ポップアップ) |
| `<leader>gi` | hunk のインラインプレビュー |

### blame / diff

| キー | 機能 |
|------|------|
| `<leader>gb` | 行の blame 表示 (誰がいつ変更したか) |
| `<leader>gd` | diff 表示 (HEAD との比較) |
| `<leader>gD` | diff 表示 (`~` = 前のコミットとの比較) |

### quickfix

| キー | 機能 |
|------|------|
| `<leader>gq` | バッファの変更箇所を quickfix に送る |
| `<leader>gQ` | 全バッファの変更箇所を quickfix に送る |

### トグル

| キー | 機能 |
|------|------|
| `<leader>gtb` | current line blame の ON/OFF |
| `<leader>gtd` | 削除行の表示 ON/OFF |
| `<leader>gtw` | word diff の ON/OFF |

### テキストオブジェクト

| キー | モード | 機能 |
|------|--------|------|
| `ih` | o, x | hunk を選択。`dih` で hunk 削除、`yih` で hunk ヤンク |

## 典型的なフロー

```
]c          → hunk を巡回
<leader>gp  → 変更内容を確認
<leader>gs  → 良ければステージ
<leader>gr  → 不要ならリセット
```
