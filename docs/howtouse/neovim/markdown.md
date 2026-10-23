# Markdown — 編集環境一式

Markdown ファイル編集に関わるプラグインと設定をひとまとめにしたドキュメント。

設定は `lua/plugins/lang/markdown/`（filetype、autolist、treesitter、skk-bridge）と、`lua/features/` の `render_markdown.lua`、`img_clip.lua`、`diagram.lua` にある。marksman は `features.nix` の `lspServers` で入り、`lua/features/lsp.lua` が有効にする。

## 構成プラグイン

| プラグイン | 役割 |
|-----------|------|
| `render-markdown.nvim` | バッファ内装飾レンダリング + 数式の Unicode 近似 |
| `autolist.nvim` | 箇条書きの自動継続 + Tab/Shift-Tab で outline 増減 |
| `img-clip.nvim` | クリップボード画像の貼り付けとリンク挿入 |
| `marksman` (LSP) | 見出しシンボル、Wiki-link 補完、ジャンプ |
| `diagram.nvim` | Mermaid 等の図ブロックを抽出してインラインプレビュー |
| `image.nvim` | バッファ内に画像を表示する基盤 (diagram.nvim の依存) |

Markdown を開くと、折り返し（`wrap`、`linebreak`、`breakindent`）、スペルチェック（`spelllang` は `en,cjk` で日本語を誤検知しない）、`conceallevel = 2` が設定される。

## render-markdown.nvim

ノーマルモードでは装飾して表示し、挿入モードでは生の Markdown に戻す。

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

依存 (`modules/home-manager/dev/neovim/features.nix` の機能ごとに注入):

| パッケージ | 提供 | 用途 |
|-----------|------|------|
| `python3Packages.pylatexenc` | `latex2text` コマンド | LaTeX → Unicode 変換 |
| `tree-sitter` | `tree-sitter` CLI | `latex` parser のビルド (※下記) |

treesitter parser として `latex` が `lang/markdown/treesitter.lua` の `ensure_installed` に含まれている。`render-markdown.nvim` は `markdown_inline` parser で `$...$` ブロックを検出し、injection で `latex` parser に内部を解析させる二段構え。**`latex` parser を入れないと extmark が一切置かれず `:RenderMarkdown debug` が "no marks on row" になる**。

`latex` parser は nvim-treesitter の parser リストで `requires_generate_from_grammar = true` 扱いなので、初回 `:TSInstall latex` 時に `tree-sitter generate` で grammar.js から parser.c を生成する。そのため `tree-sitter` CLI と nodejs (`withNodeJs = true` で注入済) が PATH 上に必要。新環境セットアップでは `ensure_installed` により自動でこのフローが走るので、手動で `:TSInstall` する必要はない。

自動導入の一覧は、言語 spec と共通 spec のどちらが先に読まれても保持する。
読み込み順によって一覧が空になっていた不具合と回帰チェックは
[spec マージの設計](../../architecture/neovim/spec-merge.md) を参照。
設定変更後は Neovim を再起動する。初回のパーサ導入が完了した後に Markdown を開き直し、
ノーマルモードで数式の行からカーソルを外すと Unicode 近似表示を確認できる。

### サポートされない記法

| 記法 | 例 | 状態 |
|------|------|------|
| dollar 記法 | `$...$`, `$$...$$` | ✓ サポート |
| AMS 記法 inline | `\(...\)` | ✗ render-markdown が非対応 |
| AMS 記法 block | `\[...\]` | ✗ 同上 |

`\[...\]` 形式の数式は通常 markdown のテキストとしてしか表示されない。`$...$` 系で書くこと。

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

1. **zettelkasten vault の `attachments/`**（`local.profile.zettelkastenRoot` 配下）に画像を保存
2. ファイル名は `YYYY-MM-DD-HH-MM-SS.png`
3. カーソル位置に現在ファイルからの相対パスで `![](../../../modules/home-manager/dev/neovim/config/docs/plugins/.../attachments/...)` の Markdown リンクを挿入

> 保存先は `features.nix` が `local.profile.zettelkastenRoot` から生成する
> `require("config.nix").data.img_clip.dir` を使う。vault が未設定なら img_clip 機能は読み込まない。

| キー | 動作 |
|------|------|
| `<leader>p` | クリップボード画像を貼り付け |

保存先は Obsidian の `attachmentFolderPath="attachments"` と物理的に一致し、rclone bisync で
Google Drive に同期される単一フォルダ（設定した vault の `attachments/`）へ集約される。
同期の仕組みは [zettelkasten 添付同期のドキュメント](../zettelkasten-attachments-sync.md)を参照。

**依存ツール**: Wayland 環境では `wl-clipboard`、X11 環境では `xclip` が必要。
`modules/home-manager/dev/neovim/features.nix` の clipboard 機能が両方を、img_clip 機能が wl-clipboard を導入する。
不在時は起動時に WARN が出る。

## diagram.nvim + image.nvim — Mermaid プレビュー

Markdown 内の mermaid コードブロックを、ブラウザを開かずに **バッファ内インラインで**
PNG プレビュー表示する。kitty の graphics protocol を使うため、
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
3. **カーソルをそのブロックに置く**と、数秒後にレンダリング結果が表示される

初回は `mmdc` が内部で Chromium ヘッドレスを起動するため数秒重い。
2 回目以降はキャッシュされて高速。

### 表示はカーソル行の 1 枚のみ

`only_render_image_at_cursor = true`（表示方式は `"inline"`）を markdown と typst の
両統合に設定しており、**カーソルが乗っている図/画像だけ**が表示される。カーソルを
外すと消える。

この設定は、WezTerm がリサイズのたびに表示中の画像を全部送り直してフリーズする問題（[wezterm#7400](https://github.com/wezterm/wezterm/issues/7400)）を避けるために入れた。端末は kitty に移ったので、この理由は今は当たらない。全部を表示するように戻すかは、kitty で確かめてから決める。

typst 統合は image.nvim 側で既定有効なため、markdown と同じ設定を明示的に入れてある
（未指定だと typst バッファだけ全画像表示のままになる）。

### 再描画のタイミング

`features/diagram.lua` の `opts.events.render_buffer` で再描画トリガを
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

> 図を即座に再描画したい場合は `:lua require("diagram").render()` を手動実行する。

### 同時実行数の制限（mmdc スロットリング）

トリガを間引いても、**複数図を含む .md を初回に開いた瞬間**は全図が一斉にキャッシュ
ミスし、mmdc が同時に大量起動する問題が残る（8 図同時起動で Chromium 系 466 プロセス／
ピーク RSS 数十 GB を実測）。diagram.nvim には同時実行数の制限機能が無いため、
`features/diagram.lua` で mermaid renderer の `render` を**上限付きキュー**でラップしている。

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
            └─ image.nvim kitty の graphics protocol で画像表示
                 └─ magick (luarock) 画像処理
```

外部ツール (`modules/home-manager/dev/neovim/features.nix` の diagram / treesitter で注入済み):

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
- 代わりに `features.nix` の `diagram.luaPackages = ps: [ ps.magick ];` で nixpkgs 側から
  magick luarock を `package.path` に注入している

将来 image.nvim 以外で luarock 依存のプラグインを追加するときも、同じく
対応する機能の `luaPackages` に追記すれば動く。

### コマンド

| コマンド | 動作 |
|---------|------|
| `:lua require("diagram").render()` | 現在のバッファの図を再描画 |
| `:lua require("diagram").clear()` | プレビューを非表示 |
| `:checkhealth image` | image.nvim の依存（magick 等）が揃っているか確認 |

### ペイン分割時の挙動

kitty の画像はペインの境界を越えて表示されない。大きな図でも他のペインにはみ出さない。
スプリット直後に画像が消えることがあるが、`:redraw!` で復活する。
`<C-l>` は smart-splits のペイン移動に割り当てているので再描画には使えない。

## marksman (LSP)

Markdown 用 language server。LSP 経由で以下を提供:

- 見出しを document symbol として公開 → `<leader>fs` (Telescope document_symbols) でアウトライン
- Wiki-link (`[[...]]`) の補完・ジャンプ
- リンク切れの診断
- リファレンス検索

LSP 共通のキーバインド (`gd` / `grr` / `K` 等) はそのまま使える。詳細は [lsp.md](./lsp.md)。
