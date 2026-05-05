# キーバインド分類チートシート

## 覚え方の原則

- **`<leader>` で始まるもの** → which-key が教えてくれる。プレフィックスだけ覚えればOK
- **それ以外** → このページの「暗記が必要」セクションを参照

迷ったら `:Telescope keymaps` で全キーマップを検索できる。

---

## which-key に任せられるもの (プレフィックスだけ覚える)

`<leader>` を押して待つと which-key が候補を表示する。個々のキーは覚えなくていい。

| プレフィックス | カテゴリ | 詳細 |
|---------------|---------|------|
| `<leader>f` | 検索 (Telescope) | [telescope.md](./plugins/telescope.md) |
| `<leader>g` | Git (gitsigns) | [git.md](./plugins/git.md) |
| `<leader>d` | デバッグ (DAP) | [dap.md](./plugins/dap.md) |
| `<leader>l` | LSP (低頻度操作) | [lsp.md](./plugins/lsp.md) |
| `<leader>s` | 囲み操作 (surround) | [editing.md](./plugins/editing.md) |
| `<leader>b` | バッファソート (barbar) | [navigation.md](./plugins/navigation.md) |
| `<leader>m` | 1行↔複数行トグル (treesj) | [treesitter.md](./plugins/treesitter.md) |
| `<leader>o` | アウトライン (aerial) | [treesitter.md](./plugins/treesitter.md) |
| `<leader>u` | Undo ツリー (undotree) | [editing.md](./plugins/editing.md) |

---

## 暗記が必要なもの

which-key では表示されないキーバインド。カテゴリ別に分類。

### 移動・ナビゲーション

| キー | モード | 機能 | 出典 |
|------|--------|------|------|
| `j` / `k` | n | 表示行で移動 (標準の `gj`/`gk` と入れ替え) | init.lua |
| `gj` / `gk` | n | 実際の行で移動 | init.lua |
| `<C-j>` / `<C-k>` | n, x, v | 5行ジャンプ | init.lua |
| `<C-o>` / `<C-i>` | n | ジャンプリストを戻る/進む | Vim 標準 |
| `{` / `}` | n | 段落移動 | Vim 標準 |

### LSP (プレフィックスなし)

LSP がアタッチされたバッファでのみ有効。→ [lsp.md](./plugins/lsp.md)

| キー | 機能 |
|------|------|
| `gd` | 定義にジャンプ |
| `gD` | 宣言にジャンプ |
| `gi` | 実装にジャンプ |
| `gr` | 参照一覧 |
| `K` | ホバードキュメント |
| `<C-s>` | シグネチャヘルプ |
| `[d` / `]d` | 前/次の診断にジャンプ |

### ブラケットジャンプ `[` / `]` 系

| キー | 機能 | プラグイン |
|------|------|-----------|
| `[d` / `]d` | 前/次の診断 | LSP |
| `[s` / `]s` | 前/次のシンボル | aerial |
| `[c` / `]c` | 前/次の Git hunk | gitsigns |

### コメント

デフォルトの `gc`/`gb` 系。→ [editing.md](./plugins/editing.md)

| キー | モード | 機能 |
|------|--------|------|
| `gcc` | n | 行コメントトグル |
| `gc` + motion | n | 行コメント (例: `gcip`, `gc5j`) |
| `gc` | v | 選択範囲を行コメント |
| `gbc` | n | ブロックコメントトグル |
| `gb` | v | 選択範囲をブロックコメント |
| `gcO` / `gco` / `gcA` | n | コメント行を上/下に挿入、行末に追加 |

### 検索

| キー | モード | 機能 | 出典 |
|------|--------|------|------|
| `/` + pattern | n | 検索 | Vim 標準 |
| `n` / `N` | n | 次/前のマッチ (hlslens 連携) | hlslens |
| `*` / `#` | n | カーソル下の単語で検索 | hlslens |
| `g*` / `g#` | n | 部分一致で検索 | hlslens |
| `<Esc><Esc>` | n | 検索ハイライト解除 | init.lua |

### バッファ操作

| キー | モード | 機能 | 出典 |
|------|--------|------|------|
| `gt` / `gT` | n | 次/前のバッファ | barbar |
| `<A-1>` 〜 `<A-9>` | n | バッファ番号で直接移動 | barbar |
| `<A-0>` | n | 最後のバッファ | barbar |
| `<A-<>` / `<A->>` | n | バッファを左/右に移動 | barbar |
| `<A-p>` | n | バッファをピン留め | barbar |
| `<C-p>` | n | バッファピック (1文字で選択) | barbar |
| `<C-S-p>` | n | バッファピックで削除 | barbar |
| `<C-w>c` | n | バッファを閉じる | barbar |

### 編集

| キー | モード | 機能 | 出典 |
|------|--------|------|------|
| `d` | x | ブラックホール削除 (レジスタを汚さない) | init.lua |
| `p` | x | ペースト (レジスタを上書きしない) | init.lua |
| `<C-a>` / `<C-x>` | n, v | インクリメント/デクリメント | dial.nvim |
| `g<C-a>` / `g<C-x>` | n, v | 連番インクリメント/デクリメント | dial.nvim |

### テキスト選択 (ビジュアルモード)

| キー | 機能 | 出典 |
|------|------|------|
| `.` | スマート選択 (連打で拡大) | textsubjects |
| `;` | コンテナ外側を選択 | textsubjects |
| `i;` | コンテナ内側を選択 | textsubjects |
| `,` | 前の選択に戻る | textsubjects |
| `ih` | Git hunk を選択 | gitsigns |

### テキストオブジェクト (y/d/c と組み合わせ)

Vim 標準だが頻出のもの。

| キー | 対象 |
|------|------|
| `iw` / `aw` | 単語 / 単語+空白 |
| `i"` / `a"` | 引用符内 / 引用符含む |
| `i(` / `a(` | 括弧内 / 括弧含む |
| `i{` / `a{` | 波括弧内 / 波括弧含む |
| `ip` / `ap` | 段落内 / 段落+前後空行 |
| `ih` | Git hunk (gitsigns) |

### モード切替・特殊

| キー | モード | 機能 | 出典 |
|------|--------|------|------|
| `<C-f>` | i, c, n | Esc の代わり | init.lua |
| `<C-j>` | i, c | SKK (日本語入力) ON/OFF | skkeleton |
| `<C-Q>` | n | ウィンドウリサイズモード | winresizer |

### 補完 (挿入モード)

| キー | 機能 | 出典 |
|------|------|------|
| `<C-space>` | 補完を手動で開く | blink.cmp |
| `<C-n>` / `<C-p>` | 次/前の候補 | blink.cmp |
| `<CR>` | 候補を確定 | blink.cmp |
| `<C-e>` | 補完をキャンセル | blink.cmp |
| `<Tab>` / `<S-Tab>` | スニペットの次/前のプレースホルダ | blink.cmp |
| `<C-g>s` | 囲みを追加 (挿入モード) | surround |
