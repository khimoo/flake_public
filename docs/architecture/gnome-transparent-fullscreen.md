# 全画面の半透明ウィンドウを透かす mutter パッチ

設定ファイル: `modules/nixos/gnome-transparent-fullscreen.nix`、`packages/mutter-transparent-fullscreen/`

使い方は [docs/howtouse/cli-tools/kitty.md](../howtouse/cli-tools/kitty.md) の「透明度」を参照。

**mutter が全画面の黒い下地を選べるようになったら、パッチと置換を外す。**

## 問題

GNOME の Wayland セッションで kitty（`background_opacity 0.75`）を全画面にすると、背後が黒くなり、壁紙も下のウィンドウも見えない。
最大化なら透ける。
XWayland 経由で動かしていた wezterm（`enable_wayland = false`）では起きなかった。

## 原因

xdg-shell の `xdg_toplevel.set_fullscreen` に次の規定がある。

> If the fullscreened surface is not opaque, the compositor must make sure that other screen content not part of the same surface tree (made up of subsurfaces, popups or similarly coupled surfaces) are not visible below the fullscreened surface.

mutter 49.4 は `src/compositor/meta-window-actor-wayland.c` の `maybe_configure_black_background` でこれを実装している。
全画面を受け入れた Wayland ウィンドウの下に不透明な黒い actor を差し込み、差し込まないのは不透明なサーフェスがモニタ全体を覆うときだけにしている。
kitty は `background_opacity` が 1 未満だと opaque region を宣言しない（kitty 0.44.0 の `glfw/wl_window.c` の `update_regions`）ので、黒が入る。
X11 クライアント用の `meta-window-actor-x11.c` にはこの処理がないので、XWayland のウィンドウは透ける。

- 規定の文言は wayland-protocols の f68bafc（2017-11-21）で入った。コミットは、全画面のサイズ規定を緩める理由に「hardware optimizations」を挙げている。
- mutter の黒い下地は 909616b（MR !2338、2022-10-10 マージ）で入った。発端の mutter #2084 は、libdecor と Wine の Wayland バックエンドがこの規定を前提にしていることを挙げている。
- sway の emersion は、この規定が半透明の全画面による偽の認証ダイアログも防ぐとしている（sway #4040）。

## 判断

mutter にパッチを当て、`system.replaceDependencies` で差し替える。
desktop と spin713 で `local.gnome.transparentFullscreen.enable` を有効にした。

パッチは `meta-window-actor-wayland.c` の 2 か所を変える。

1. モニタ全体を覆うサーフェスには、半透明でも黒を敷かない。モニタより小さいサーフェスを中央に置き、周りを黒で埋める処理は残す。
2. 黒を敷かない半透明のサーフェスを direct scanout の候補にしない。

2 つ目が要るのは、`meta_window_actor_wayland_get_scanout_candidate` が、全画面でサーフェスが 1 つなら不透明かどうかを見ずに scanout の候補にするからである。
黒の下地がある間は、scanout しても見た目は変わらなかった。
下地をなくすと、scanout では下のウィンドウとの合成が行われず、再び黒く見える。
`meta-compositor-view-native.c` の scanout 判定にも不透明度の条件はない。

### replaceDependencies を選んだ理由

overlay で mutter を上書きすると、依存する gnome-shell、gnome-control-center、gnome-session、GSConnect、gnome-browser-connector のハッシュが変わり、binary cache が使えなくなる。
mutter の依存（glib や mesa など）は nixpkgs を更新するたびにほぼ変わるので、そのたびにこれらを再ビルドすることになる。

置換なら、ビルドするのは mutter だけで済む（2026-09-26、mutter 49.4、デスクトップで 126 秒）。
依存する側は store パスの文字列置換でコピーする。
置換前の spin713 で、対象は 30 パス、NAR で合計 71.5 MiB だった。

spin713 は `hosts/nixos-spin713/chrome-audio.nix` ですでに `replaceDependencies` を使っている。
評価のたびに元のシステム closure を実体化する IFD の負担は、もう払っている。
デスクトップでも全画面の半透明ウィンドウを使うため、この評価負担を受け入れて有効にした。

## 代償

- xdg-shell の規定（must）から外れる。kitty 以外でも、opaque region を宣言せずにアルファ付きのバッファで全画面にする Wayland アプリは、下の画面が透ける。該当するアプリは調べていない。候補は EGL や Vulkan で描くゲーム、動画プレイヤー、Wine で、`weston-simple-egl` の現行版は全画面のとき自分で不透明にするので当たらない。
- そうした表示の崩れを、アプリや mutter に不具合として報告できない。
- nixpkgs は `replaceDependencies` を短期の手段として作っている（「This should be a short term solution」）。置換は `nix-store --dump` の出力を `sed` で書き換える処理なので、圧縮されたファイルの中のパスは置換されない。置換が漏れていないかは、closure に元の mutter が残っていないかで確かめる。
- mutter は nixpkgs を更新するたびにビルドされ、desktop と spin713 の評価（`scripts/check.sh` と CI を含む）はそのビルドを待つ。
- パッチが当たらなくなるとビルドが止まる。黙って無効になることはない。
- パッチで mutter の ABI を変えてはいけない。gnome-shell は元の mutter のヘッダでビルドされたまま使われる。

## 検証

2026-09-26、nixpkgs b6018f8、mutter 49.4 で確かめた。

- パッチを当てた mutter のビルドが通る。
- spin713 の `system.build.toplevel` をビルドし、closure にある mutter が、パッチ版を置換したもの 1 つだけであることを確認した。`pkgs.mutter` と、音声回避策の置換を経た元の mutter は含まれていない。gnome-shell が参照する mutter もそれだけだった。
- デスクトップで gnome-shell を `--headless --virtual-monitor 800x600` で起動し、赤い不透明の kitty の上に `background_opacity 0.5` の青い kitty を全画面で重ねて撮影した。元の gnome-shell では画面全体が暗い青（青 50% を黒に重ねた色）になり、置換後の gnome-shell では緑の壁紙と赤い kitty が透けた。

撮影には gnome-shell の `org.gnome.Shell.Screenshot` を使った。
この D-Bus メソッドは許可リストにあるバス名の持ち主からしか受け付けないので、`org.gnome.SettingsDaemon.MediaKeys` を取得したプロセスから呼んだ。
`dbus-run-session` は、一時ディレクトリに向けた `HOME` と `XDG_*` を設定してから起動する必要がある。
D-Bus から起動される dconf-service などはデーモンの環境を引き継ぐので、そうしないと本物の `~/.config/dconf/user` に書き込む。

ヘッドレスでは KMS の CRTC がないので、direct scanout は起きない。
パッチの 2 つ目（scanout の候補から外す変更）は、ソースを読んだ判断にとどまる。
実機で全画面の kitty がまだ黒いなら、ここを疑う。

2026-09-29、desktop でも `system.build.toplevel.drvPath` の評価と、置換先の mutter のビルドが通った。
実機の GNOME セッションでの表示は、世代切替と再ログイン後に確認する。

2026-10-01、nixos-26.05（nixpkgs 7fc6f2c）の mutter 50.4 でも確かめた。
nixpkgs 側のパッチを当てたソースに、このパッチはずれなく当たり（`patch --dry-run`）、パッチ版のビルドが通った。
desktop と spin713 の `system.build.toplevel` をビルドし、closure にある mutter がパッチ版 1 つだけであることを確認した。spin713 では、音声回避策の置換で参照を書き換えたパッチ版になる。
26.05 での実機の表示は、世代切替と再ログイン後に確認する。

## 見直しの契機

- mutter が全画面の黒い下地を選べるようになったとき、または wayland-protocols #116 の透明な全画面の要求が入り、kitty がそれを使うようになったとき。
- パッチが当たらなくなったとき。追従しないなら、最大化と kitty の `hide_window_decorations yes` で代わりにする。
- GNOME をやめたとき。

## 退けた案

- 最大化で済ませる: パッチは要らないが、上部バーが残る。
- kitty を XWayland で動かす（`linux_display_server x11`）: 設定 1 行で済む。ただし kitty の X11 版は IBus の D-Bus プロトコルでしか IME とやり取りしないので、fcitx5-skk で入力できるかを確かめ直す必要があり、分数スケーリングでは文字がぼやける。
- overlay で mutter を上書きする: 上の再ビルドの負担がある。
- 別のコンポジタに移る: sway と niri も全画面で黒を敷き、メンテナは意図した動作としている。Hyprland v0.56.2 は壁紙を描くが、全画面の下のウィンドウを透明度 0 にして隠すので、下のウィンドウは見えない。KWin はこの規定を強制していない（wayland-protocols #116、2022 年時点）。

## 参考

- [xdg-shell.xml（wayland-protocols）](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/stable/xdg-shell/xdg-shell.xml)
- [wayland-protocols f68bafc: xdg-shell: Soften fullscreen geometry requirements](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/commit/f68bafc)
- [wayland-protocols #116: Transparent fullscreen surfaces](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/issues/116)
- [mutter MR !2338](https://gitlab.gnome.org/GNOME/mutter/-/merge_requests/2338)、[mutter #2084](https://gitlab.gnome.org/GNOME/mutter/-/issues/2084)、[mutter #2520](https://gitlab.gnome.org/GNOME/mutter/-/work_items/2520)
- [mutter 49.4 `meta-window-actor-wayland.c`](https://gitlab.gnome.org/GNOME/mutter/-/blob/49.4/src/compositor/meta-window-actor-wayland.c)
- [sway #4040](https://github.com/swaywm/sway/issues/4040)、[niri discussion #1399](https://github.com/niri-wm/niri/discussions/1399)、[kitty #7338](https://github.com/kovidgoyal/kitty/issues/7338)
