## lazy.nvim spec マージ前提のディレクトリ設計

`lua/plugins/lang/<name>/` 以下から `nvim-treesitter` や `nvim-lspconfig` 等の **共通プラグインに言語固有の設定を後付けで差し込む**、という設計方針の根拠。

## 背景: 何を解決したいか

`markdown` のような「トピック」に関する設定は、性質ごとに複数のプラグイン spec に分散しがち:

- `ftplugin` 的な設定 (wrap, spell, conceallevel 等)
- markdown 専用プラグイン (render-markdown.nvim, autolist.nvim 等)
- `nvim-treesitter` の `ensure_installed` に追加するパーサ (`markdown`, `markdown_inline`, `latex`, `mermaid`)
- `nvim-lspconfig` の override (現状は marksman はデフォルトで使うが、将来カスタマイズの可能性)
- 他プラグインとの連携 (skkeleton ↔ autolist の bridge 等)

これを「トピック中心」のディレクトリにまとめたい。しかし `nvim-treesitter` の spec は元々 `plugins/treesitter.lua` で集中管理されており、`ensure_installed` を言語ごとに追記するには「同じプラグインの設定を複数箇所で書く」必要が出てくる。

## 採用方針 (case-F): lazy.nvim の spec マージ

lazy.nvim は **同じプラグイン名で複数 spec が存在すると自動で deep-merge** する。これを使い、`lang/<name>/<sub>.lua` から共通プラグインの opts を追記する。

### 具体例: treesitter parser の追加

`lang/markdown/treesitter.lua`:

```lua
return {
  "nvim-treesitter/nvim-treesitter",
  opts = function(_, opts)
    opts.ensure_installed = opts.ensure_installed or {}
    vim.list_extend(opts.ensure_installed, { "markdown", "markdown_inline", "mermaid", "latex" })
  end,
}
```

`plugins/treesitter.lua` には `ensure_installed = {}` のベース spec を置き、各言語モジュールが list_extend で追加する。

### 具体例: LSP override の追加 (現状は未使用、設計のみ)

`plugins/lsp/init.lua` で `opts.servers` を table として宣言:

```lua
opts = {
  servers = {
    tinymist = { settings = { ... } },
    nil_ls = { settings = { ... } },
  },
},
config = function(_, opts)
  -- opts.servers を読んで各サーバーを vim.lsp.config で有効化
end,
```

将来 marksman の override が必要になった際は `lang/markdown/lsp.lua` で:

```lua
return {
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    opts.servers = opts.servers or {}
    opts.servers.marksman = { settings = { ... } }
  end,
}
```

を返せば、ベースの `opts.servers` に deep-merge される。

## 設計上のトレードオフ

### 採用したもの (case-F)

- 凝集度: 言語/トピック単位で関連設定を 1 ディレクトリに集約できる
- 結合度: 共通プラグイン側が言語を知らない (一方向の依存)
- 拡張性: 新しい言語を追加するときは `lang/<name>/` を作るだけ。中央の編集が要らない

### 採用しなかった案

#### 案 A: 単純なファイル分割

`lang/markdown.lua` を `lang/markdown/{filetype,render,autolist,...}.lua` に分割するだけ。

- 短所: `ensure_installed` や LSP override は中央 (`treesitter.lua`, `lsp/init.lua`) に書く必要があり、「markdown 関連の設定」が物理的に複数箇所に散る
- 「半分集約」止まりで、case-F より中途半端

#### 案 D: トピックレジストリ (LazyVim の extras に近い)

`config/topics.lua` のようなレジストリを作り、各トピックモジュールが `topics.register("markdown", { ftplugin = ..., treesitter = ..., lsp = ... })` を呼ぶ。各プラグイン spec はレジストリから設定を集める。

- 短所: 抽象化が過剰。個人 dotfiles の規模感では機構コストが見合わない
- 短所: デバッグ時に「どの設定がどこから来たか」の追跡性が下がる

## トレードオフ (case-F の弱点)

- **`:Lazy` のデバッグ感**: 「marksman の最終 opts は何か」を知るには、関連 spec を grep して spec マージの結果を頭で再現する必要がある (LazyVim 経験者なら慣れた手順)
- **lazy.nvim 固有**: packer.nvim や mini.deps、rocks.nvim では同じ機構が無い (または挙動が違う)。パッケージマネージャを乗り換える際に再設計が要る
- **opts のリスト merge は注意が必要**: `opts = { ensure_installed = {...} }` の table 形式は配列を上書きする。配列追加には `opts = function(_, opts) vim.list_extend(...) end` の関数形式を使うこと

## 現在の適用箇所

| ベース spec | 拡張側 | 形式 |
|------------|--------|------|
| `plugins/treesitter.lua` (nvim-treesitter) | `lang/markdown/treesitter.lua` | function 形式で `ensure_installed` を list_extend |
| `plugins/lsp/init.lua` (nvim-lspconfig) | (現状は同ファイル内に集約; 将来 `lang/<x>/lsp.lua` から拡張する余地) | table 形式で `opts.servers.<name>` を deep-merge |

## 参考

- lazy.nvim 公式: [Spec Merging](https://lazy.folke.io/spec#%EF%B8%8F-spec-merging)
- LazyVim の extras 実装が同パターンの参考になる: `lua/lazyvim/plugins/extras/lang/*.lua`
