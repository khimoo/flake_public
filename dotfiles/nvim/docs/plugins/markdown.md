# Markdown — 編集環境一式

Markdown ファイル編集に関わるプラグインと設定をひとまとめにしたドキュメント。

> 設定: `dotfiles/nvim/lua/plugins/lang/markdown.lua`
> LSP (marksman) は `modules/home-manager/dev.nix` の `lspServers` 経由で導入され、
> `dotfiles/nvim/lua/plugins/lsp/init.lua` が自動で有効化する。

## 構成プラグイン

| プラグイン | 役割 |
|-----------|------|
| `render-markdown.nvim` | バッファ内装飾レンダリング |
| `autolist.nvim` | 箇条書きの自動継続 + Tab/Shift-Tab で outline 増減 |
| `img-clip.nvim` | クリップボード画像の貼り付けとリンク挿入 |
| `marksman` (LSP) | 見出しシンボル、Wiki-link 補完、ジャンプ |

## filetype オプション (ftplugin 相当)

Markdown ファイルを開くと自動適用:

| オプション | 値 | 効果 |
|-----------|-----|------|
| `wrap` | true | 長い行を画面端で視覚的に折り返し |
| `linebreak` | true | 単語の途中で折らない (英文向け) |
| `breakindent` | true | 折り返し行をインデント揃え |
| `spell` | true | スペルチェック有効化 |
| `spelllang` | en, cjk | 日本語を誤検知しない |
| `conceallevel` | 2 | render-markdown の装飾を効かせる |

なお `j`/`k` の表示行移動は `keymaps.lua` でグローバル設定済み。

## render-markdown.nvim

ノーマルモードでは装飾表示、挿入モードでは生の Markdown に戻る (編集を邪魔しない)。

| 要素 | 装飾 |
|------|------|
| `# 見出し` | レベルに応じた背景色 + アイコン |
| テーブル | Unicode 罫線で整形表示 |
| `- [x]` チェックボックス | アイコン化 |
| コードブロック | 背景色 + 言語ラベル |
| `[link](url)` | リンクアイコン |
| `**太字**`, `*斜体*` | フォント装飾 |
| `---` 水平線 | 全幅の罫線 |
| `> 引用` | 左ボーダー + 背景色 |

| コマンド | 操作 |
|---------|------|
| `:RenderMarkdown toggle` | 装飾表示の ON/OFF 切替 |
| `:RenderMarkdown enable` | 装飾表示を有効化 |
| `:RenderMarkdown disable` | 装飾表示を無効化 |

## autolist.nvim — 箇条書きの outline 操作

| キー | モード | 動作 |
|------|--------|------|
| `<CR>` | i | 同じレベルで新しい bullet を作る |
| `<Tab>` | i | bullet を 1 段深くする (demote) |
| `<S-Tab>` | i | bullet を 1 段浅くする (promote) |
| `o` | n | 下の行に新 bullet |
| `O` | n | 上の行に新 bullet |

順序付きリスト (`1.`, `2.`, ...) はインデント変更時に自動で番号振り直し。

**Tab の競合について**: `blink.cmp` のスニペット placeholder ジャンプ (`<Tab>`) と
バッファローカルではないため衝突する。Markdown でスニペット展開中の `<Tab>` は
bullet 操作に取られる点に注意。

## img-clip.nvim — クリップボード画像の貼り付け

スクリーンショットをクリップボードに保持した状態で `<leader>p`:

1. 画像を `<カレントファイルのあるディレクトリ>/assets/` に保存
2. ファイル名は `YYYY-MM-DD-HH-MM-SS.png`
3. カーソル位置に `![](assets/...)` の Markdown リンクを挿入

| キー | 動作 |
|------|------|
| `<leader>p` | クリップボード画像を貼り付け |

**依存ツール**: Wayland 環境では `wl-clipboard`、X11 環境では `xclip` が必要。
両方とも `modules/home-manager/dev.nix` の `nvimPluginDeps` で導入される。
不在時は起動時に WARN が出る。

## marksman (LSP)

Markdown 用 language server。LSP 経由で以下を提供:

- 見出しを document symbol として公開 → `<leader>fs` (Telescope document_symbols) でアウトライン
- Wiki-link (`[[...]]`) の補完・ジャンプ
- リンク切れの診断
- リファレンス検索

LSP 共通のキーバインド (`gd` / `grr` / `K` 等) はそのまま使える。詳細は [lsp.md](./lsp.md)。
