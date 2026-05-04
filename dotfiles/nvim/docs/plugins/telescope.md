# Telescope

ファジーファインダー。ファイル検索、テキスト検索、LSP 連携など Neovim の検索の中核。

- 設定ファイル: `lua/plugins/telescope.lua`
- 依存: plenary.nvim, ripgrep, telescope-file-browser.nvim, telescope-media-files.nvim, project.nvim

## プラグイン

### telescope.nvim

ファジー検索エンジン本体。

### telescope-file-browser.nvim

Telescope 内でディレクトリツリーを辿れるファイラー拡張。`hijack_netrw = true` で netrw を置き換えている。

### project.nvim

Git リポジトリのルートに自動で `cd` してくれる。`find_files` 等が常にプロジェクトルートから検索される。

## キーバインド

### 検索系 (最も使う)

| キー | 機能 | 説明 |
|------|------|------|
| `<leader>ff` | find_files | ファイル名でファジー検索。2-3文字で絞れる |
| `<leader>fg` | live_grep | プロジェクト全体のテキスト検索 (ripgrep) |
| `<leader>fb` | buffers | 開いているバッファの一覧・切り替え |
| `<leader>fo` | oldfiles | 最近開いたファイルの一覧 |

### LSP 連携

| キー | 機能 | 説明 |
|------|------|------|
| `<leader>fd` | diagnostics | LSP の警告・エラー一覧 |
| `<leader>fs` | lsp_document_symbols | 現在ファイル内の関数・型・変数の一覧 |
| `<leader>fr` | lsp_references | カーソル下のシンボルの参照箇所一覧 |

### その他

| キー | 機能 | 説明 |
|------|------|------|
| `<leader>fh` | help_tags | Neovim のヘルプをファジー検索 |
| `<leader>fe` | file_browser | ディレクトリツリーを辿る。ファイル作成・リネーム・削除も可能 |
| `<leader>ft` | Telescope commands | Telescope の全コマンド一覧 |

### Telescope ウィンドウ内の操作

| キー | 動作 |
|------|------|
| `<C-n>` / `<C-p>` | 候補を上下に移動 |
| `<CR>` | 選択して開く |
| `<C-f>` | キャンセル (Esc) |
| `<C-x>` | 水平分割で開く |
| `<C-v>` | 垂直分割で開く |
| `<C-t>` | 新しいタブで開く |

### file_browser 内の操作 (挿入モード)

| キー | 動作 |
|------|------|
| `<C-j>` | SKK 入力を有効化 (skkeleton 連携) |
| `<C-f>` | Esc |

## 設定のポイント

- `theme = "dropdown"` で file_browser はドロップダウン表示
- `hijack_netrw = true` で `:edit <dir>` が file_browser に置き換わる
