# kitty

設定ファイル: `modules/home-manager/gui/kitty/kitty.conf`（配線は `modules/home-manager/gui/kitty.nix`）

設計判断は [docs/architecture/kitty.md](../../architecture/kitty.md) を参照。

`kitty.conf` は out-of-store symlink なので、編集はリポジトリのファイルを直接直せばよく rebuild は要らない。
反映は kitty 側で `Ctrl+Shift+F5`（設定の再読込）。ただし `listen_on` の変更だけは再読込では効かず、
kitty の起動し直しが要る。

## 呼び名

kitty は「pane」という語を使わない。このリポジトリでは kitty の語彙に合わせつつ、kitty の `window` を
「**タブ内ウィンドウ**」と書く。階層は下から順に、タブ内ウィンドウ → タブ → OS ウィンドウ。

| 呼び名 | kitty の語 | 実体 |
|--------|-----------|------|
| タブ内ウィンドウ | window | シェルや Neovim が動く単位。タブの中で分割される |
| タブ | tab | タブ内ウィンドウの集合。レイアウト（splits / stack）を持つ |
| OS ウィンドウ | os_window | タブの集合。ウィンドウマネージャから見える窓 |

## キー体系

`Ctrl+a` に続けて「階層」「動詞」の順に押す。kitty ネイティブのキー列なので、モードには入らない
（途中で無関係なキーを押せばそこで打ち切られる）。

階層は `w` タブ内ウィンドウ / `t` タブ / `o` OS ウィンドウ。
動詞は `c` 作る / `f` フォーカス / `e` 並べ替え / `m` 別の入れ物へ移す / `r` サイズ / `x` 閉じる。

| 動詞 | `Ctrl+a w …`（タブ内ウィンドウ） | `Ctrl+a t …`（タブ） | `Ctrl+a o …`（OS ウィンドウ） |
|------|--------------------------------|---------------------|------------------------------|
| 作る | `c` 左右に分割 | `c` 新しいタブ | `c` 新しい OS ウィンドウ |
| フォーカス | `f` 視覚的に選ぶ | `f` 一覧から選ぶ | `f` 直前の OS ウィンドウ |
| 並べ替え | `e` 他のウィンドウと入れ替え | `e` 次へ / `Shift+E` 前へ | （無し） |
| 移す | `m` 行き先のタブを選ぶ | `m` 行き先の OS ウィンドウを選ぶ | （無し） |
| サイズ | `r` リサイズモードに入る | （無し） | （無し） |
| 閉じる | `x` 確認して閉じる | `x` タブを閉じる | `x` OS ウィンドウを閉じる |

空欄が 3 つあるのは割当て漏れではない。OS ウィンドウには移す先の上位階層が無く、その並べ替えは
ウィンドウマネージャの領分で、タブは表示領域を OS ウィンドウから受け取るので固有のサイズを持たない。

### 行き先を選ばずに移す

`Ctrl+a w m` は行き先を一覧から選ぶが、選ばずに済ませたいときは以下を使う。

| キー | 動作 |
|------|------|
| `Ctrl+a w [` | 左隣のタブへ移す |
| `Ctrl+a w ]` | 右隣のタブへ移す |
| `Ctrl+a w n` | 新しいタブを作ってそこへ移す |
| `Ctrl+a w o` | 新しい OS ウィンドウを作ってそこへ移す |

タブについては `Ctrl+a t n` が「新しい OS ウィンドウへ移す」。

### 短縮形

wezterm で使っていた手癖をそのまま残してある。階層キーを挟まない。

| キー | 動作 |
|------|------|
| `Ctrl+a s` / `Ctrl+a v` | 上下 / 左右に分割 |
| `Ctrl+a c` | 新しいタブ |
| `Ctrl+a n` / `Ctrl+a Shift+N` | 次 / 前のタブ |
| `Ctrl+a x` | タブ内ウィンドウを閉じる |
| `Ctrl+a e` | レイアウトを回転 |
| `Ctrl+a y` | スクロールバックを開く |
| `Ctrl+a Ctrl+a` | アプリへ `Ctrl+a` を送る |

### 割当ての一覧を出す

`Ctrl+a ?` でオーバーレイが開き、`kitty.conf` の `map` 行と見出しがそのまま並ぶ。`q` で閉じる。
出所が定義そのものなので、キーを足しても一覧の側を直す必要はない。

kitty 組み込みの `Ctrl+Shift+F6`（`debug_config`）も割当てを出すが、キー列を先頭のトリガーで
まとめてしまうため、`Ctrl+a` 始まりの 30 個が 1 行に潰れて読めない。

### Neovim との分割の行き来

`Ctrl+h/j/k/l` でフォーカス移動、`Alt+h/j/k/l` でリサイズ。Neovim の分割と kitty のタブ内ウィンドウを
区別せずに跨げる。Neovim がフォーカスを持つ間は kitty 側の割当てが外れ、キーがそのまま Neovim へ渡る。

端に到達したときは反対側へ回り込む（`at_edge = "wrap"`）。

### 透明度

| キー | 動作 |
|------|------|
| `Ctrl+=` / `Ctrl+-` | 5% 上げる / 下げる |
| `Ctrl+0` | 既定の 0.75 に戻す |

## スクロールバック

`Ctrl+a y`（または kitty 既定の `Ctrl+Shift+H`）でスクロールバックが Neovim で開く。kitty 自身は
スクロールバックの検索も vi 風の選択も持たないので、そこは Neovim の機能をそのまま使う。`/` で検索、
`v` で選択、`y` でヤンク。`q` で閉じる（`ZQ` に割当ててあるので変更は破棄される）。

色は保たれる。開いた直後は末尾にいる。

この設定は Neovim 0.12 以降でしか動かない。0.11 では画面が空になる。
理由は [docs/architecture/unstable-packages.md](../../architecture/unstable-packages.md) を参照。

## 遠隔操作

`allow_remote_control socket-only` と `listen_on` を有効にしてあるので、`kitten @` でシェルから
kitty を操作できる。ソケットは `$XDG_RUNTIME_DIR/kitty.sock-<PID>`。

```sh
kitten @ --to "unix:$XDG_RUNTIME_DIR/kitty.sock-$(pgrep -x kitty | head -1)" ls
```

kitty の中から実行する場合は `KITTY_LISTEN_ON` が入っているので `--to` を省ける。

`socket-only` なので、端末に流し込まれたエスケープ列による遠隔操作は拒否される。
`cat` で悪意あるファイルを表示しても kitty を操作されない。

## wezterm から移ってきて無いもの

| wezterm の機能 | kitty での扱い |
|----------------|---------------|
| vi 風コピーモード | 組み込みでは無い。スクロールバックを Neovim で開いて代替する |
| QuickSelect | `kitten hints`（既定 `Ctrl+Shift+P` 系）が近い。画面上のパス・URL・単語をラベルで選ぶ |
| command palette | 無い |
| 配色プレビュー選択 | `kitten themes` |
