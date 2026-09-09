# 端末を wezterm から kitty へ移す

設定ファイル: `modules/home-manager/gui/kitty.nix`、`modules/home-manager/gui/kitty/kitty.conf`

使い方は [docs/howtouse/cli-tools/kitty.md](../howtouse/cli-tools/kitty.md) を参照。

## 問題

端末の階層は タブ内ウィンドウ → タブ → OS ウィンドウ の 3 層あるのに、wezterm で自由に動かせるのは
一番下の層だけだった。上の層をどう扱うかがキー割当てにも表れておらず、操作が場当たりになっていた。

整理した結果、実際に要るのは 2 つだけだった。

1. タブ内ウィンドウを別のタブへ移す
2. タブを別の OS ウィンドウへ移す

どちらも所有権の移動であって、同時表示ではない。セッションの永続化と再接続は要求に入らない。

wezterm は 1 は持つが 2 を実現する手段を持たない。

## 判断

kitty に移る。両方ともネイティブの action（`detach_window` / `detach_tab`）で足りる。

### tmux 案を退けた理由

当初は wezterm を表示端末として残し、階層の管理を tmux へ移す案を検討した。tmux なら
`join-pane` と `move-window` で 2 操作とも成立し、キー設定が端末非依存になる。

しかし要求を満たすだけなら kitty のほうが軽い。tmux 案には移動先選択 UI を自作する手間と、
session と OS ウィンドウが一対一にならない（運用規則で埋める）という代償が付く。端末非依存性も
セッション永続化も要求に入っていない利益で、それを根拠に中間レイヤを足すと、乗り換えコストを
避けるために今より重い乗り換えをすることになる。

### 実測で確かめたこと

kitty 0.44.0 で以下を remote control 越しに確認した。

- タブ内ウィンドウは pid を保ったまま、別 OS ウィンドウの既存タブへ移る
- 3 つに分割された splits レイアウトのタブは、構成も 3 つの pid も保ったまま別 OS ウィンドウへ移る
- `fcitx5-skk` の日本語入力がネイティブ Wayland で動く（`wayland_enable_ime` は既定で有効）

「kitty は Wayland で IME が動かない」という記述が web の検索上位に出るが、これは 2021 年の
Debian bug #990316 由来で現在は当たらない。

なお、タブ内ウィンドウが 1 つだけのタブを detach すると元の OS ウィンドウが空になって閉じるので、
OS ウィンドウの総数が変わらない。動いていないように見えるが正常。

## キー体系

`Ctrl+a > 階層 > 動詞` の 3 打鍵にした。階層は `w` / `t` / `o`、動詞は `c` 作る / `f` フォーカス /
`e` 並べ替え / `m` 移す / `r` サイズ / `x` 閉じる。要求の 2 操作は `Ctrl+a w m` と `Ctrl+a t m`。

- kitty ネイティブのキー列（`map ctrl+a>w>m`）を使い、キーボードモード（`map --new-mode`）は使わない。
  モードは状態を持つので、抜け忘れると次の入力が化ける。キー列なら無関係なキーで自然に打ち切られる。
- 3 打鍵は操作の発見性のための規則で、頻用するものは階層キーを挟まない短縮形を別名として残した。
  wezterm での手癖をそのまま使い続けられる。
- 18 マス中 3 マスが構造的に空く。OS ウィンドウには移す先の上位階層が無く、その並べ替えは
  ウィンドウマネージャの領分で、タブは表示領域を OS ウィンドウから受け取るので固有のサイズを
  持たない。空欄に別の操作を当てると規則が壊れるので空けたままにする。

呼び名は kitty の語彙に合わせた。ただし kitty の `window` は日本語で「ウィンドウ」と書くと OS
ウィンドウと紛れるので「タブ内ウィンドウ」と表記する。

`detach_tab ask` の選択肢は OS ウィンドウを**アクティブタブのタイトル**で表示する。同名のタブが
並んでいると見分けが付かない、という弱点は受け入れる。

### 一覧を kitty.conf 自身から作る

30 個の割当てを覚えきれないので `Ctrl+a ?` で一覧を出す。中身は `kitty.conf` の `map` 行と
`# ---` 見出しを `grep` で抜き出してオーバーレイのページャに流すだけで、一覧を別に持たない。
キーを足したときに一覧の側を直し忘れて実態とずれる、という状態を作らないため。

kitty 組み込みの `debug_config`（`Ctrl+Shift+F6`）では代用できない。`kitty/debug_config.py` の
`compare_opts` が生の `sequence_map` を無視し、表示用の `as_sc` がキー列を先頭のトリガーで
まとめるので、`Ctrl+a` 始まりの 30 個が 1 行に潰れる。

一覧からは 2 種類の行を落とす。`--when-focus-on` で始まる smart-splits の割当て解除行は動作を
持たないため、そしてこの `map ctrl+a>?` 行自身は自分の実装（長い `grep` のパイプライン）を
そのまま曝すため。後者の除外は `^map ctrl\+a>\?` と明示して書く。除外条件を
`--when-focus-on` だけにしておくと、その文字列を引数に含むこの行が偶然に自己排除され、
条件を書き換えた瞬間に一覧へ紛れ込む。

## 遠隔操作を有効にする範囲

`allow_remote_control socket-only` と `listen_on unix:${XDG_RUNTIME_DIR}/kitty.sock` を有効にする。

smart-splits.nvim の kitty backend が `kitty @` を使うので remote control が要る。backend は
`KITTY_LISTEN_ON` の有無で自分が有効かを判定するため、`listen_on` も必須。

`yes` ではなく `socket-only` を選んだのは、TTY 経由の遠隔操作を拒否するため。`yes` だと端末に
流し込まれたエスケープ列で kitty を操作できてしまい、悪意あるファイルを `cat` するだけで
任意のコマンドを実行される。ソケット経由だけに絞れば、その経路が塞がったうえで smart-splits は
そのまま動く。

ソケットを `/tmp` ではなく `$XDG_RUNTIME_DIR` に置いたのは、こちらが 0700 のユーザー専有
ディレクトリだから。抽象ソケット（`unix:@mykitty`）は network namespace 内の他ユーザーからも
到達できるので使わない。

## smart-splits の kitty backend

Neovim の分割と kitty のタブ内ウィンドウを `Ctrl+hjkl` で区別せず跨ぐ設定は、smart-splits.nvim が
担う。kitty 側は `--when-focus-on var:IS_NVIM` で割当てを外し、キーをそのまま Neovim へ渡す。
`IS_NVIM` は smart-splits が起動時に OSC 1337 で立てる kitty の user var。

backend が呼ぶ kitten 3 つ（`neighboring_window.py` / `relative_resize.py` / `split_window.py`）は、
plugin 同梱の `install-kittens.bash` が `~/.config/kitty/` へ命令的にコピーする作りになっている。
nixpkgs の `vimPlugins.smart-splits-nvim` が同じファイルを同梱していて（lazy が入れる版と
バイト一致を確認済み）、`xdg.configFile` で宣言的に置けるので、スクリプトは実行しない。

`at_edge` は `stop` にしている。`mux/init.lua` の `at_edge ~= 'wrap' and current_pane_at_edge(...)`
という短絡のおかげで、`wrap` を選んでも kitty 側の未実装スタブは呼ばれず動作自体は壊れない。
しかし 2025-11-21 版の `config.lua` は kitty を検出すると既定値を `stop` に置き、明示指定した `wrap` も
`setup` 時に `stop` へ上書きしたうえで警告を通知する。`lazy = false` で読むので起動直後に hit-enter
プロンプトが出る。上書きされる以上 kitty 下で wrap は選べないため、設定値を実際の挙動に合わせた。

## スクロールバック

kitty はスクロールバックの検索も vi 風の選択も持たない。`show_scrollback` は外部ページャに渡すだけ。
そこで `scrollback_pager` を Neovim に向け、検索と選択を Neovim の機能で埋める。

この設定は Neovim 0.12 以降でしか動かないので、`overlays/unstable-packages.nix` で
`neovim-unwrapped` を unstable から取っている。経緯は
[unstable-packages.md](./unstable-packages.md) を参照。

## 設定の置き方

`kitty.conf` は `mkOutOfStoreSymlink` でリポジトリを直接指す。wezterm と同じ形で、キー割当ての
調整が rebuild なしで試せる。

フォント名は Nix 側が `font.conf` を生成し、`kitty.conf` から `include font.conf` で取り込む。
kitty の `include` は symlink の指す先ではなく、設定ファイルが置かれた場所（`~/.config/kitty/`）を
基準に解決するので、リポジトリへの symlink と Nix の生成物を同じディレクトリに共存させられる。
wezterm 側の `font.lua` と同じ手口。

フォント定義（`plemoljp-nf` / "PlemolJP Console NF"）と `TERMINAL_TRANSPARENT` は
`modules/home-manager/gui/default.nix` へ引き上げた。前者は両方の端末が同じものを使うため
`_module.args` で配り、後者は端末の種類を問わず Neovim の背景透過 autocmd が読む値だから。

## 移行の段取り

既定端末はまだ切り替えず、wezterm と並走させる。両方入っている状態で kitty を日常的に使い、
不足が出ないと確かめてから既定を移す。切替は別の判断として残す。

## 関連

- [unstable-packages.md](./unstable-packages.md) — Neovim 0.12 を unstable から取っている理由
- [docs/howtouse/cli-tools/kitty.md](../howtouse/cli-tools/kitty.md) — 操作の一覧
