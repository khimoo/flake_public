# Neovim 設定ガイド

この Neovim 設定の使いこなしドキュメント。

## プラグイン一覧

| カテゴリ | プラグイン | ドキュメント |
|----------|-----------|-------------|
| 検索 | telescope, project.nvim | [telescope.md](./plugins/telescope.md) |
| ファイラー | oil.nvim | [telescope.md](./plugins/telescope.md) |
| LSP | nvim-lspconfig | [lsp.md](./plugins/lsp.md) |
| 構文解析 | treesitter, treesj, textsubjects, textobjects, aerial | [treesitter.md](./plugins/treesitter.md) |
| テスト | neotest, neotest-rust | [neotest.md](./plugins/neotest.md) |
| Git | gitsigns, diffview | [git.md](./plugins/git.md) |
| デバッグ | nvim-dap, dap-view, dap-go | [dap.md](./plugins/dap.md) |
| 編集支援 | Comment, surround, dial, hlslens, undotree, bqf, guess-indent | [editing.md](./plugins/editing.md) |
| 補完 | blink.cmp | [completion.md](./plugins/completion.md) |
| 日本語入力 | skkeleton, fcitx5 連携 | [skkeleton.md](./plugins/skkeleton.md) |
| ナビゲーション | barbar, winresizer | [navigation.md](./plugins/navigation.md) |
| 外観 | lualine, hlchunk, fidget, which-key | [appearance.md](./plugins/appearance.md) |
| Rust | rustaceanvim, rustowl | [lang-rust.md](./plugins/lang-rust.md) |
| ノート管理 | telekasten | [telekasten.md](./plugins/telekasten.md) |

## リファレンス

- [キーバインド分類チートシート](./cheatsheet.md) — 「覚える必要があるもの」と「which-key に任せられるもの」の分類一覧
- [キーバインド変更メモ](./keybindings-memo.md) — デファクトスタンダードに合わせた修正の記録

---

# ワークフローごと使い方

## 1. 新しいプロジェクトのコードを読む

```
<leader>ff      ファイル名で検索してエントリポイントを開く
<leader>fs      ファイル内の関数・型の一覧を見て構造を把握
<leader>fS      ワークスペース全体からシンボルを検索 (型名・関数名で探す)
gd              気になる関数/型の定義に飛ぶ
<C-o>           戻る (<C-i> で逆方向)
grr             「これどこで使われてる？」
K               型やドキュメントをホバーで確認
<leader>o       aerial でアウトライン表示
[s / ]s         シンボル間をジャンプして流し読み
]f / [f         次/前の関数にジャンプ
```

→ [lsp.md](./plugins/lsp.md), [telescope.md](./plugins/telescope.md), [treesitter.md](./plugins/treesitter.md)

**コツ**: `gd` → `<C-o>` のループがコードリーディングの基本動作。何回でも遡れる。

## 2. バグを探して修正する

```
<leader>fd      diagnostics 一覧で全エラー/警告を俯瞰
[d / ]d         エラー箇所をジャンプで巡回
(CursorHold)    250ms 停止で診断フロートが自動表示される
gd              エラーに関連する定義に飛ぶ
<leader>fg      live_grep でエラーメッセージや関連文字列を検索
(修正する)
gra             code action で自動修正候補があれば適用
<leader>lF      フォーマット
```

→ [lsp.md](./plugins/lsp.md), [telescope.md](./plugins/telescope.md)

## 3. リファクタリング

```
gd              変更対象の定義に移動
grr             影響範囲を確認 (どこで使われているか)
grn             LSP rename でプロジェクト全体を一括リネーム
gcc             不要なコードをコメントアウト (まず様子見)
gcc             問題なければもう一度 gcc で戻して dd で削���
```

→ [lsp.md](./plugins/lsp.md), [editing.md](./plugins/editing.md)

**コメント操作のパターン**:
- 1行: `gcc`
- 複数行: ビジュアルモードで選択 → `gc`
- motion: `gcip` (段落まるごと), `gc5j` (5行分)

## 4. 日常の編集

### ファイル間移動

```
<leader>ff      ファイル名で検索して開く (最も速い)
<leader>fb      開いているバッファ一覧から選ぶ
<leader>fo      最近開いたファイルから選ぶ
gt / gT         次/前のバッファタブ
<C-p>           barbar のバッファピック (1キーで選べる)
<leader>fe      Oil でディレクトリをバッファ表示 (ファイル作成・リネーム・移動時)
```

→ [telescope.md](./plugins/telescope.md), [navigation.md](./plugins/navigation.md)

### テキスト編集

```
yiw             単語をコピー
ciw             単語を書き換え (削除+挿入モード)
ci"             引用符の中身を書き換え
da(             括弧ごと削除
<C-a> / <C-x>  数値やboolのインクリ��ント/デクリメント (dial.nvim)
v → .           textsubjects: スマート選択 (連打で範囲拡大)
v → ;           textsubjects: コンテナ外側を選択
<leader>m       treesj: 1行↔複数行のトグル
```

→ [editing.md](./plugins/editing.md), [treesitter.md](./plugins/treesitter.md)

### 囲み操作 (surround)

```
<leader>sysiw"  word を "word" に
<leader>scs"'   "x" を 'x' に
<leader>sds"    "x" を x に
```

→ [editing.md](./plugins/editing.md)

### 検索

```
/pattern        検索 (hlslens でマッチ数が表示される)
n / N           次/前のマッチ
* / #           カーソル下の単語を前方/後方検索
<Esc><Esc>      検索ハイライト解除
<leader>fg      プロジェクト全体を grep (Telescope)
```

→ [editing.md](./plugins/editing.md), [telescope.md](./plugins/telescope.md)

## 5. Git 操作

```
]c / [c         次/前の変更箇所 (hunk) にジャンプ
<leader>gp      hunk のプレビュー (変更内容を確認)
<leader>gs      hunk をステージ
<leader>gr      hunk をリセット (変更取消)
<leader>gS      バッファ全体をステージ
<leader>gb      行の blame 表示
<leader>gd      diff 表示
ih              テキストオブジェクト: hunk 選択 (dih, yih 等)
```

→ [git.md](./plugins/git.md)

**典型フロー**: `]c` で巡回 → `<leader>gp` で確認 → `<leader>gs` でステージ

## 6. デバッグ

```
<leader>db      ブレークポイント設置/解除
<leader>dc      デバッグ開始/続行
<leader>do      ステップオーバー
<leader>di      ステップイン
<leader>dO      ステップ��ウト
<leader>dr      REPL を開く
```

→ [dap.md](./plugins/dap.md), [lang-rust.md](./plugins/lang-rust.md)

## 7. テスト実行

```
<leader>tt      カーソル位置のテストを実行
<leader>tf      ファイル全体のテストを実行
<leader>tl      前回のテストを再実行
<leader>ts      テスト一覧パネルの表示/非表示
<leader>to      テスト出力を確認
<leader>td      テストを DAP でデバッグ実行
```

→ [neotest.md](./plugins/neotest.md)

**典型フロー**: テスト書く → `<leader>tt` → 実装 → `<leader>tl` で再実行

## 8. 日本語入力

```
<C-j>           insert/command モードで SKK を ON/OFF
<C-f>           Esc (ノーマルモードに戻る + fcitx5 自動 OFF)
```

→ [skkeleton.md](./plugins/skkeleton.md)

## 9. ウィンドウ・タブ管理

```
<C-Q>           winresizer 起動 (hjkl でサイ���変更)
gt / gT         次/前のバッファ
<A-1>〜<A-9>    バッファ番号で直接移動
<C-w>c          バッファを閉じる
<C-p>           バッファピック
```

→ [navigation.md](./plugins/navigation.md)

## 10. init.lua のカスタムキーバインド

Vim 標準の動作を変更しているもの。

| キー | モード | 機能 |
|------|--------|------|
| `<C-f>` | i, c, n | Esc の代わり |
| `<C-j>` / `<C-k>` | n, x, v | 5行ジャンプ (加速移動) |
| `j` / `k` | n | 表示行で移動 (`gj`/`gk` と入れ替え) |
| `x` モードの `d` | x | ブラックホールレジスタに削除 (レジスタを汚さない) |
| `x` モードの `p` | x | ペースト時にレジスタを上書きしない |
| `<Esc><Esc>` | n | 検索ハイライト解除 |

### ユーザーコマンド

| コマンド | 機能 |
|----------|------|
| `:Redir <cmd>` | Ex コマンドの出力を新しいバッファに表示 |
