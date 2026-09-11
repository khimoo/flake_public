# Treesitter 関連

構文解析ベースのハイライト、テキストオブジェクト、コード整形。

- 設定ファイル: `lua/plugins/treesitter.lua`
- ノード単位の選択キー: `lua/config/keymaps.lua`

## プラグイン

### nvim-treesitter

構文解析エンジン。`branch = "main"` を指定している。main は master とは別物の書き直しで、設定に互換性がない。

パーサは `opts.ensure_installed` に集めて `require("nvim-treesitter").install()` に渡す。`ensure_installed` は main ブランチのオプションではなく、言語モジュールからベース spec へ渡すための本リポジトリ内の名前。追加の仕組みは [spec-merge.md](../architecture/spec-merge.md) を参照。

main はハイライトを自動で有効化しない。`FileType` で `vim.treesitter.start` を呼ぶのが利用者の責務になったため、`config` 内の autocmd で全 filetype に対して試し、パーサが無い場合は `pcall` で握り潰している。

`install()` は非同期なので、パーサ未導入の言語は初回起動時にハイライトが遅れて付く。CLI の `tree-sitter` 0.26.1 以上が要る (経緯は [unstable-packages.md](../../../../../../../docs/architecture/unstable-packages.md))。

### treesj

1行↔複数行のトグル。引数リストやテーブルを展開/折りたたみ。

| キー | 機能 |
|------|------|
| `<leader>m` | 1行と複数行をトグル |

例:
```
-- <leader>m で切り替え
local t = { a = 1, b = 2, c = 3 }
-- ↕
local t = {
  a = 1,
  b = 2,
  c = 3,
}
```

### ノード単位の選択 (Neovim 組み込み)

以前は nvim-treesitter-textsubjects を使っていたが、main ブランチで消えた `nvim-treesitter.query` と `ts_utils` に依存しており、upstream も 2025-02 で止まっているため外した。代わりに Neovim 0.12 組み込みの incremental selection (`:h treesitter-incremental-selection`) を使う。

組み込みの既定キーはこの4組。

| キー | 機能 |
|------|------|
| `an` | 親ノードを選択 |
| `in` | 子ノードを選択 |
| `]n` / `[n` | 次/前のノードを選択 |
| `]N` / `[N` | 次/前のノードへ選択を拡張 |

指の癖を残すため、`lua/config/keymaps.lua` で旧キーを割り当て直している。

| キー | 割り当て先 |
|------|-----------|
| `.` | `an` |
| `;` | `an` |
| `i;` | `in` |

textsubjects は言語ごとの手書きクエリで「意味のあるまとまり」を選んでいたのに対し、組み込みは構文木のノードを素直に辿る。同じ範囲を取るのに `.` の連打回数が増えることがある。旧 `,` (前の選択に戻る) に一対一で対応するキーは無く、縮める方向は `in` が担う。

### aerial.nvim

コードのアウトライン (関数・型の一覧) をサイドパネルに表示。

| キー | 機能 |
|------|------|
| `<leader>o` | アウトラインの表示/非表示トグル |
| `[s` | 前のシンボルにジャンプ |
| `]s` | 次のシンボルにジャンプ |

`[s`/`]s` は `[d`/`]d` (診断ジャンプ) と対になる覚え方。

### nvim-treesitter-textobjects

treesitter の構文木に基づいたテキストオブジェクトとジャンプ。`daf` (関数ごと削除)、`cia` (引数を書き換え) など operator と組み合わせて使う。

こちらも `branch = "main"`。master 時代の `require('nvim-treesitter.configs').setup({ textobjects = ... })` は無くなり、`require("nvim-treesitter-textobjects").setup()` で挙動だけ設定し、キーは `vim.keymap.set` から `select` / `move` / `swap` の各モジュールを呼ぶ形になった。

#### テキストオブジェクト (select)

| キー | 対象 |
|------|------|
| `af` / `if` | 関数 (outer / inner) |
| `ac` / `ic` | クラス・impl (outer / inner) |
| `aa` / `ia` | 引数 (outer / inner) |

#### ジャンプ (move)

| キー | 機能 |
|------|------|
| `]f` / `[f` | 次/前の関数の先頭 |
| `]F` / `[F` | 次/前の関数の末尾 |
| `]a` / `[a` | 次/前の引数 |

#### 引数スワップ (swap)

| キー | 機能 |
|------|------|
| `<leader>a` | 引数を次と入れ替え |
| `<leader>A` | 引数を前と入れ替え |

例:
```rust
// カーソルが `b` にあるとき <leader>a で:
fn foo(a: i32, b: i32, c: i32) → fn foo(a: i32, c: i32, b: i32)
```
