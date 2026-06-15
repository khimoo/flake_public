# Markdown — 編集環境一式

Markdown ファイル編集に関わるプラグインと設定をひとまとめにしたドキュメント。

> 設定: `modules/home-manager/dev/neovim/config/lua/plugins/lang/markdown/` 配下に
> サブモジュール (filetype / render / autolist / img-clip / treesitter / skk-bridge) で分割。
> LSP (marksman) は `modules/home-manager/dev/lsp.nix` の `lspServers` 経由で導入され、
> `lua/plugins/lsp/init.lua` が自動で有効化する。サーバー固有の override が必要に
> なった際は、本ディレクトリに `lsp.lua` を追加して `nvim-lspconfig` の
> `opts.servers.marksman` を spec マージで宣言する想定。

## 構成プラグイン

| プラグイン | 役割 |
|-----------|------|
| `render-markdown.nvim` | バッファ内装飾レンダリング |
| `autolist.nvim` | 箇条書きの自動継続 + Tab/Shift-Tab で outline 増減 |
| `img-clip.nvim` | クリップボード画像の貼り付けとリンク挿入 |
| `marksman` (LSP) | 見出しシンボル、Wiki-link 補完、ジャンプ |
| `diagram.nvim` | Mermaid 等の図ブロックを抽出してインラインプレビュー |
| `image.nvim` | バッファ内に画像を表示する基盤 (diagram.nvim の依存) |

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

### skkeleton 連携 (skk-bridge.lua)

skkeleton 有効中は insert-mode の `<CR>` が skkeleton に横取りされ、autolist の
`<CR>` マップが発火しない。これを補うため `skk-bridge.lua` が
`User skkeleton-handled` イベントでバッファ行数の増加を監視し、改行が挿入された
場合のみ `AutolistNewBullet` を呼ぶ。変換確定時の `<CR>` (`eggLikeNewline=true`
により改行なし) では行数が変わらないため、誤発火しない。

## img-clip.nvim — クリップボード画像の貼り付け

スクリーンショットをクリップボードに保持した状態で `<leader>p`:

1. 画像を `<カレントファイルのあるディレクトリ>/assets/` に保存
2. ファイル名は `YYYY-MM-DD-HH-MM-SS.png`
3. カーソル位置に `![](assets/...)` の Markdown リンクを挿入

| キー | 動作 |
|------|------|
| `<leader>p` | クリップボード画像を貼り付け |

**依存ツール**: Wayland 環境では `wl-clipboard`、X11 環境では `xclip` が必要。
両方とも `modules/home-manager/dev/neovim/default.nix` の `nvimPluginDeps` で導入される。
不在時は起動時に WARN が出る。

## diagram.nvim + image.nvim — Mermaid プレビュー

Markdown 内の mermaid コードブロックを、ブラウザを開かずに **バッファ内インラインで**
PNG プレビュー表示する。WezTerm の Kitty graphics protocol を使うため、
ターミナル内で完結する。

### 使い方

1. `.md` ファイルを開く
2. 以下のような mermaid ブロックを書く:
   ````
   ```mermaid
   graph TD
     A[Start] --> B[End]
   ```
   ````
3. 数秒待つと、コードブロックの下にレンダリング結果が表示される

初回は `mmdc` が内部で Chromium ヘッドレスを起動するため数秒重い。
2 回目以降はキャッシュされて高速。

### 構成と依存

```
.md バッファ
  └─ diagram.nvim         mermaid ブロックを treesitter で抽出
       └─ mmdc            PNG にレンダリング (内部で Chromium ヘッドレス使用)
            └─ image.nvim WezTerm の Kitty graphics protocol で画像表示
                 └─ magick (luarock) 画像処理
```

外部ツール (すべて `modules/home-manager/dev/neovim/default.nix` で注入済み):

| 依存 | 用途 |
|------|------|
| `mermaid-cli` (mmdc) | mermaid → PNG レンダリング |
| `imagemagick` (magick CLI) | 画像のリサイズ/変換 |
| `magick` luarock | image.nvim の画像処理バインディング |
| treesitter `mermaid` parser | コードブロック抽出 (`ensure_installed` 経由) |

### Nix 環境固有の注意

lazy.nvim の **luarocks 統合は無効化**してある (`lua/config/lazy.lua` 参照):

- `rocks.enabled = false`: lazy.nvim 内蔵の hererocks (Lua 5.1 + luarocks の埋め込み環境) は
  Nix で読み取り専用な `/nix/store` 配下では組めないため無効化
- `pkg.sources = { "lazy", "packspec" }`: image.nvim の `.rockspec` を読まないようにする。
  読むと「magick 依存が未解決」とみなされ "Too many rounds of missing plugins" エラーになる
- 代わりに `programs.neovim.extraLuaPackages = ps: [ ps.magick ];` で nixpkgs 側から
  magick luarock を `package.path` に注入している

将来 image.nvim 以外で luarock 依存のプラグインを追加するときも、同じく
`extraLuaPackages` に追記すれば動く。

### コマンド

| コマンド | 動作 |
|---------|------|
| `:Diagram show` | 現在のバッファの図を強制再レンダリング |
| `:Diagram hide` | プレビューを非表示 |
| `:checkhealth image` | image.nvim の依存（magick 等）が揃っているか確認 |

### ペイン分割時の挙動

WezTerm の画像はペインの境界を越えて表示されない。大きな図でも他のペインにはみ出さない。
スプリット直後に画像が消えることがあるが、`<C-l>` (画面再描画) で復活する。

## marksman (LSP)

Markdown 用 language server。LSP 経由で以下を提供:

- 見出しを document symbol として公開 → `<leader>fs` (Telescope document_symbols) でアウトライン
- Wiki-link (`[[...]]`) の補完・ジャンプ
- リンク切れの診断
- リファレンス検索

LSP 共通のキーバインド (`gd` / `grr` / `K` 等) はそのまま使える。詳細は [lsp.md](./lsp.md)。
