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
| `render-markdown.nvim` | バッファ内装飾レンダリング + 数式の Unicode 近似 |
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

### 数式 (`$...$`, `$$...$$`) の Unicode 近似表示

LaTeX 風の数式を Unicode 文字列に変換して inline 表示する。

| 記法 | 入力例 | 表示 |
|------|--------|------|
| inline math | `$x^2 + y^2 = r^2$` | `x² + y² = r²` |
| display math | `$$\sum_{i=0}^{n} i$$` | `∑ᵢ₌₀ⁿ i` (中央寄せ extmark) |

**実装**: render-markdown.nvim が `latex2text` (pylatexenc) を起動して LaTeX を Unicode
近似へ変換し、extmark で描画する。**画像ではない**ため:

- 利点: ターミナル要件なし (Kitty graphics protocol 不要)、依存軽量
- 制約: 行列・複雑な分数・integral with limits などは粗くなる

依存 (`modules/home-manager/dev/neovim/default.nix` の `nvimPluginDeps` で注入):

| パッケージ | 提供 | 用途 |
|-----------|------|------|
| `python3Packages.pylatexenc` | `latex2text` コマンド | LaTeX → Unicode 変換 |
| `tree-sitter` | `tree-sitter` CLI | `latex` parser のビルド (※下記) |

treesitter parser として `latex` が `lang/markdown/treesitter.lua` の `ensure_installed` に含まれている。`render-markdown.nvim` は `markdown_inline` parser で `$...$` ブロックを検出し、injection で `latex` parser に内部を解析させる二段構え。**`latex` parser を入れないと extmark が一切置かれず `:RenderMarkdown debug` が "no marks on row" になる**。

`latex` parser は nvim-treesitter の parser リストで `requires_generate_from_grammar = true` 扱いなので、初回 `:TSInstall latex` 時に `tree-sitter generate` で grammar.js から parser.c を生成する。そのため `tree-sitter` CLI と nodejs (`withNodeJs = true` で注入済) が PATH 上に必要。新環境セットアップでは `ensure_installed` により自動でこのフローが走るので、手動で `:TSInstall` する必要はない。

### サポートされない記法

| 記法 | 例 | 状態 |
|------|------|------|
| dollar 記法 | `$...$`, `$$...$$` | ✓ サポート |
| AMS 記法 inline | `\(...\)` | ✗ render-markdown が非対応 |
| AMS 記法 block | `\[...\]` | ✗ 同上 |

`\[...\]` 形式の数式は通常 markdown のテキストとしてしか表示されない。`$...$` 系で書くこと。

### 高品質レンダリングへの拡張余地

真の PDF 品質で表示したい場合は、`diagram.nvim` の renderer に LaTeX → PNG 変換を
プラグインする (texlive + dvipng or matplotlib.mathtext 等) 余地がある。現状は
mermaid のみが diagram.nvim で画像化されている。

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

1. **zettelkasten vault の `attachments/`**（`~/sagyo/zettelkasten/attachments`）に画像を保存
2. ファイル名は `YYYY-MM-DD-HH-MM-SS.png`
3. カーソル位置に現在ファイルからの相対パスで `![](.../attachments/...)` の Markdown リンクを挿入

> 保存先は暫定でハードコード。**将来 neovim 設定を独立モジュール化する際に option 化**する予定
> （TODO は `img-clip.lua` に記載）。現状は zettelkasten 以外の vault で貼っても保存先がここに固定される。

| キー | 動作 |
|------|------|
| `<leader>p` | クリップボード画像を貼り付け |

保存先は Obsidian の `attachmentFolderPath="attachments"` と物理的に一致し、rclone bisync で
Google Drive に同期される単一フォルダ（`~/sagyo/zettelkasten/attachments`）へ集約される。
同期の仕組みは [zettelkasten 添付同期のドキュメント](../../../../../../../docs/howtouse/zettelkasten-attachments-sync.md)を参照。

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

### 再描画のタイミング

`diagram.lua` の `opts.events.render_buffer` で再描画トリガを
`{ "InsertLeave", "BufWinEnter", "BufWritePost" }` に絞っている。

- `BufWinEnter` — ファイルを開いた／ウィンドウに表示した時
- `InsertLeave` — 挿入モードを抜けた時（＝入力が一区切りした時）
- `BufWritePost` — 保存した時（ノーマルモードでの編集を拾う）

**なぜ `TextChanged` を外したか**: diagram.nvim のデフォルトは `TextChanged` を含み
**打鍵ごと**に再描画する。`diagram.nvim` は同時実行数を制限せず、キャッシュミスした
図の数だけ `mmdc`（1 図 ≈ 3 秒、内部で Chromium 起動）を**一斉に**起動するため、
mermaid ブロックを複数持つ .md では初回描画や編集中に Chromium プロセスが大量に
湧いて RAM を食い潰し、システムが swap スラッシングを起こしてフリーズする。
トリガを間引くことで、編集が一区切りした時だけ再描画する。

> 図を即座に再描画したい場合は `:Diagram show` を手動実行する。

### 同時実行数の制限（mmdc スロットリング）

トリガを間引いても、**複数図を含む .md を初回に開いた瞬間**は全図が一斉にキャッシュ
ミスし、mmdc が同時に大量起動する問題が残る（8 図同時起動で Chromium 系 466 プロセス／
ピーク RSS 数十 GB を実測）。diagram.nvim には同時実行数の制限機能が無いため、
`diagram.lua` で mermaid renderer の `render` を**上限付きキュー**でラップしている。

- 同時に走る `mmdc` は `MAX_CONCURRENT`（既定 2）個まで。残りはキューで待機。
- 図は 2 個ずつ順次レンダリングされ、完了ごとにバッファを再描画して表示される
  （多数の図では全部表示されるまで数秒かかるが、その間もエディタは固まらない）。
- キャッシュ済みの図は即座に表示される（mmdc を起動しない）。

**実装上の注意**: patch 対象は `require("diagram/renderers/mermaid")` を**スラッシュ記法**で
require したテーブル。ドット記法だと `package.loaded` 上で別モジュール扱いになり二重ロード
され、patch がプラグイン側に反映されない。キャッシュパスの生成式も mermaid.lua と一致させて
いる（ズレると mmdc の出力先と表示先が食い違い画像が出ない）。

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
