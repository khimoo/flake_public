# Neovim 設定ガイド

この Neovim の設定で使うプラグインとキー操作の案内。

## プラグイン一覧

| カテゴリ | プラグイン | ドキュメント |
|----------|-----------|-------------|
| 検索 | telescope, project.nvim | [telescope.md](./telescope.md) |
| ファイラー | oil.nvim | [telescope.md](./telescope.md) |
| LSP | nvim-lspconfig | [lsp.md](./lsp.md) |
| 構文解析 | treesitter, treesj, textobjects, aerial | [treesitter.md](./treesitter.md) |
| テスト | neotest, neotest-rust | [neotest.md](./neotest.md) |
| Git | gitsigns, diffview | [git.md](./git.md) |
| デバッグ | nvim-dap, dap-view, dap-go | [dap.md](./dap.md) |
| 編集支援 | Comment, surround, dial, hlslens, undotree, guess-indent | [editing.md](./editing.md) |
| 診断・quickfix | trouble.nvim | [trouble.md](./trouble.md) |
| 補完 | blink.cmp | [completion.md](./completion.md) |
| 日本語入力 | skkeleton | [skkeleton.md](./skkeleton.md) |
| ナビゲーション | harpoon2, smart-splits | [navigation.md](./navigation.md), [smart-splits.md](./smart-splits.md) |
| 外観 | lualine, hlchunk, fidget, which-key | [appearance.md](./appearance.md) |
| Markdown | render-markdown.nvim, autolist.nvim, img-clip.nvim, marksman, diagram.nvim, image.nvim | [markdown.md](./markdown.md) |
| Rust | rustaceanvim, rustowl | [lang-rust.md](./lang-rust.md) |
| Typst | tinymist, typst-preview.nvim | [lang-typst.md](./lang-typst.md) |

## リファレンス

- [キーバインド分類チートシート](./cheatsheet.md): 覚える必要があるキーと、which-key に任せられるキーの一覧。このリポジトリで変えたキーもここにある

## 設計方針 (architecture/)

- [lazy.nvim spec マージ前提のディレクトリ設計](../../architecture/neovim/spec-merge.md): `lang/<name>/` から共通プラグインの opts を後付け差し込みする設計の根拠
- [プラグインと外部ツールを機能として組にする](../../architecture/neovim/features.md): `lua/features/` の spec と Nix の依存を組にし、機能を外せば両方が外れる仕組み
- [lazy.nvim 本体だけを nixpkgs から取る構成](../../architecture/neovim/plugin-manager.md): 本体は nixpkgs、プラグインは lazy-lock.json で固定する役割分担と、採用しなかった案

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

→ [lsp.md](./lsp.md), [telescope.md](./telescope.md), [treesitter.md](./treesitter.md)

**コツ**: `gd` → `<C-o>` のループがコードリーディングの基本動作。何回でも遡れる。

## 2. バグを探して修正する

```
<leader>xx      diagnostics 一覧で全エラー/警告を俯瞰 (trouble)
[d / ]d         エラー箇所をジャンプで巡回
(CursorHold)    250ms 停止で診断フロートが自動表示される
gd              エラーに関連する定義に飛ぶ
<leader>fg      live_grep でエラーメッセージや関連文字列を検索
(修正する)
gra             code action で自動修正候補があれば適用
<leader>lF      フォーマット
```

→ [lsp.md](./lsp.md), [trouble.md](./trouble.md), [telescope.md](./telescope.md)

## 3. リファクタリング

```
gd              変更対象の定義に移動
grr             影響範囲を確認 (どこで使われているか)
grn             LSP rename でプロジェクト全体を一括リネーム
(新しい名前入力中もバッファ補完が効く)
.               構造体のフィールドアクセスで補完が出る
<C-k>           シグネチャヘルプで引数の型を確認
gcc             不要なコードをコメントアウト (まず様子見)
gcc             問題なければもう一度 gcc で戻して dd で削除
```

→ [lsp.md](./lsp.md), [editing.md](./editing.md), [completion.md](./completion.md)

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
gt / gT         harpoon リスト内の次/前のファイル
<leader>ha      現在のファイルを harpoon リストに追加
<leader>hh      harpoon メニューを開く
<leader>fe      Oil でディレクトリをバッファ表示 (ファイル作成・リネーム・移動時)
```

→ [telescope.md](./telescope.md), [navigation.md](./navigation.md)

### テキスト編集

```
yiw             単語をコピー
ciw             単語を書き換え (削除+挿入モード)
ci"             引用符の中身を書き換え
da(             括弧ごと削除
<C-a> / <C-x>  数値やboolのインクリメント/デクリメント (dial.nvim)
v → an          親ノードを選択 (連打で範囲拡大, 組み込み)
v → in          子ノードを選択 (縮める, 組み込み)
v → . / ;       an の別名
v → i;          in の別名
<leader>m       treesj: 1行↔複数行のトグル
```

→ [editing.md](./editing.md), [treesitter.md](./treesitter.md)

### 囲み操作 (surround)

```
<leader>sysiw"  word を "word" に
<leader>scs"'   "x" を 'x' に
<leader>sds"    "x" を x に
```

→ [editing.md](./editing.md)

### 検索

```
/pattern        検索 (hlslens でマッチ数が表示される)
n / N           次/前のマッチ
* / #           カーソル下の単語を前方/後方検索
<Esc><Esc>      検索ハイライト解除
<leader>fg      プロジェクト全体を grep (Telescope)
```

→ [editing.md](./editing.md), [telescope.md](./telescope.md)

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

→ [git.md](./git.md)

**典型フロー**: `]c` で巡回 → `<leader>gp` で確認 → `<leader>gs` でステージ

## 6. デバッグ

```
<leader>db      ブレークポイント設置/解除
<leader>dc      デバッグ開始/続行
<leader>do      ステップオーバー
<leader>di      ステップイン
<leader>dO      ステップアウト
<leader>dr      REPL を開く
```

→ [dap.md](./dap.md), [lang-rust.md](./lang-rust.md)

## 7. テスト実行

```
<leader>tt      カーソル位置のテストを実行
<leader>tf      ファイル全体のテストを実行
<leader>tl      前回のテストを再実行
<leader>ts      テスト一覧パネルの表示/非表示
<leader>to      テスト出力を確認
<leader>td      テストを DAP でデバッグ実行
```

→ [neotest.md](./neotest.md)

**典型フロー**: テスト書く → `<leader>tt` → 実装 → `<leader>tl` で再実行

## 8. 日本語入力

```
<C-j>           insert/command モードで SKK を ON/OFF
```

→ [skkeleton.md](./skkeleton.md)

## 9. ウィンドウ・ペイン管理

```
Ctrl+h/j/k/l    ウィンドウ/ペイン間を移動 (nvim ↔ kitty シームレス)
Alt+h/j/k/l     ウィンドウ/ペインをリサイズ
<leader><leader>h/j/k/l  バッファをスワップ (nvim 内)
gt / gT         harpoon リスト内の次/前のファイル
<leader>ha      現在のファイルを harpoon リストに追加
<leader>h1〜h5  マークしたファイルに直接移動
```

→ [navigation.md](./navigation.md), [smart-splits.md](./smart-splits.md)
