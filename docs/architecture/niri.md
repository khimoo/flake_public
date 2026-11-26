# Niri のセッションと画面配信

使い方: [Niri](../howtouse/niri.md) / [外出先からの画面配信](../howtouse/tailscale.md)
実装: [desktop.star](../../config/elements/desktop.star) / [niri_config.star](../../config/elements/niri_config.star) / [display_layout.star](../../config/elements/display_layout.star) / [niri_remote_session.star](../../config/elements/niri_remote_session.star)

## ログイン画面とアプリの共通サービスを残す

GDM をログイン画面に使い、ユーザーのセッションを Niri にする。GDM 自身が GNOME Shell などに依存するため、GNOME という名前のパッケージがクロージャにないことを受け入れ条件にしない。確認する境界は、GNOME のユーザーデスクトップ、拡張、GNOME Remote Desktop、独自 Mutter 置換が有効になっていないこと。

画面共有には `xdg-desktop-portal-gnome` と GTK portal、認証情報には GNOME Keyring を残す。固定した [nixpkgs の Niri モジュール](https://github.com/NixOS/nixpkgs/blob/e21fec321d73511849707a7585e4ea155ee4bf40/nixos/modules/programs/wayland/niri.nix) がこの組を選ぶ。Secret Service を使う [Windows VM](windows-vm.md) の資格情報も同じ保管先を使うが、Niri での解錠とブラウザ認証・画面共有は実機確認が要る。

## Home Manager の有無でセッションを分けない

Home Manager を使わない `mase` にも端末、スタートメニュー（ランチャー・通知・トレイ・電源）、ロック、ディスプレイ配置が必要なため、共通設定と常駐サービスは NixOS に置く。Quickshell ハブ（`quickshell-hub`）、`cliphist-watch`、`swayidle`、`kanshi` はシステムが提供するユーザーユニットで起動し、Home Manager に同名のデーモンを作らない。`swaylock` には設定ファイルを明示して、パッケージの既定の探索先に依存させない。単機能 UI のコンポーネント定義（`waybar` / `swaync` / `vicinae`）は比較・ロールバック用に `config/elements/` へ残している。

個人の Niri、Quickshell ハブ、kanshi の設定だけを各ユーザーの checkout に live symlink で結ぶ。既存のユーザー設定はシステム既定より優先される。システム側にはユーザー名や checkout のパスを含めない。live symlink の変更は Nix 世代のロールバックでは戻らない（[構成の境界](configuration.md)）。

## ディスプレイ配置を GUI 編集と宣言的管理で両立する

ディスプレイ配置の GUI には nixpkgs 標準の `wdisplays` を使う（固定済み nixpkgs 26.05 の `wdisplays 1.3.0`、`artizirk/wdisplays` タグ `1.3.0`）。外部の独自 GUI（`kanshi-gtk4`・`kanshi_gui`・`monitoradlo`）を独自パッケージとして保守するより負担が小さく、`wdisplays 1.3.0` の `src/store.c` が `kanshi` 設定の読み書きと `kanshictl reload` による再読み込みを標準で備えるため。

- **ディレクトリ単位の live symlink と Git 管理**: Home Manager ユーザーは `~/.config/kanshi` ディレクトリを checkout の [modules/home-manager/gui/kanshi/](../../modules/home-manager/gui/kanshi/config) へ結び、`dconf`（`network/cycles/wdisplays/save-kanshi-config`、`resources/wdisplays.gschema.xml`）で「Save to kanshi Config」を既定で有効にする。`wdisplays 1.3.0` は `g_file_set_contents`（一時ファイル作成後に `rename`）で書き戻すため、ファイル単位ではなくディレクトリ単位の symlink にしてリンク切れを防ぐ。GUI 保存後は `git diff` とコミットで宣言的に履歴を残し、他ホストへ共有する。
- **非 Home Manager ユーザーへのフォールバック**: `kanshi 1.8.0`（`emersion/kanshi` タグ `v1.8.0`、`main.c`）は既定で `$XDG_CONFIG_HOME/kanshi/config` のみを探し、無ければ終了する。`kanshi.service` はラッパ（`kanshi-session`）経由で起動し、ユーザーの `kanshi/config` が読めるならそれを、読めない場合（`mase` や checkout 未配置時）はリポジトリの同じ内容から生成した `/etc/kanshi/config` を渡す。
- **`output *` の汎用プロファイルを置かない**: `wdisplays 1.3.0`（`src/store.c` の `match_profile`）は接続出力数とプロファイル内の `output` 数が一致するとき `output *` に一致し、そのプロファイルを上書きする。1 画面構成を保存した際に `output *` が特定ディスプレイの解像度・倍率へ書き換わるのを防ぐため、既定ファイルには `output *` を置かない。`kanshi 1.8.0`（`config.c`・`main.c`）はプロファイル 0 件の設定を受け入れ、一致しない構成では出力を変更しないため、未知の単体接続や Sunshine の仮想出力（`sunshine-extend`）にも干渉しない。
- **ホスト分岐を避ける**: `wdisplays 1.3.0`（`src/store.c` の `append_criteria`）は新規プロファイルの識別子に `Make Model Serial` を使うため、1 つの `kanshi/config` を `nixos-desktop` と `nixos-spin713` でそのまま共有できる（[構成の境界](configuration.md#ホストによる違いを受け持つ場所)）。
- **名前付きプロファイル切替・管理（`kanshi-switch`＋Quickshell ハブ連携）**: `wdisplays 1.3.0` には名前付きプロファイルの切替・起動時既定の変更・2 つ目以降の個別編集・削除の UI が無いため、[kanshi-switch.py](../../modules/home-manager/gui/kanshi-switch.py) が `fuzzel 1.14.1` と一時ファイル経由の `wdisplays --kanshi` 呼び出しを組み合わせてこれらを完結させる。起動時の既定は別状態ファイルを持たず `kanshi/config` 先頭へのブロック移動で宣言的に表す。編集中に `wdisplays 1.3.0`（`src/store.c`）が `kanshictl reload` を呼んで既存の先頭プロファイルへ巻き戻すのを防ぐため、`wdisplays` 実行中だけ `PATH` 先頭に no-op の `kanshictl` を置き、ウィンドウ終了後に本体 `config` を原子的差し替えして実 `kanshictl reload` / `switch` を実行する。日々の切替は [RightColumn.qml](../../modules/home-manager/gui/quickshell/hub/RightColumn.qml) が `kanshi-switch --status-json` を読んでピルボタン（既定に `★` 付き）として表示し、`quickshell_hub` の `requires` に `display_layout` を明示する。

## KDL の寄与と手編集を分ける

生成するキー、XKB、環境変数などは `generated.kdl` にまとめ、設定の入口から include する。同じファイル内で `input` や `binds` を重複させるとエラーになるが、別ファイルの節は合成される。include の後のキー割り当ては、同じキーの生成設定より優先される。[Niri 26.04 の ConfigPart](https://github.com/niri-wm/niri/blob/8ed0da44d974c32c6877d2f4630c314da0717ecb/niri-config/src/lib.rs) がこの区別を実装する。

寄与同士の同一キーや、値が異なる環境変数は confgen で拒否する。生成成功だけでは KDL の正しさを保証できないため、[構文の check](../../tests/elements/niri.nix) は、寄与なし・デスクトップ一式・センサー付きの設定を Niri 自身で読む。

XDG Autostart は `xdg-desktop-autostart.target` に統一する。通常の `niri.service` と headless のユニットがこれを要求する。dex を追加すると二重起動になる。アプリを直接 systemd サービスにしない理由と背景ワークスペースは [既定アプリ](default-apps.md) を参照。

## 仮想出力のために fork を固定する

[パッケージ](../../packages/niri-virtual-outputs/default.nix) は PR [#3800](https://github.com/niri-wm/niri/pull/3800) の `willybarret/niri@7fd585dd44ed67644977dd9561bb6e8b3837f8f7` を固定する。nixpkgs の Niri 26.04 にそのまま当たらない差分であり、仮想出力と `NIRI_BACKEND=headless` を使うために必要となる。上流へ取り込まれ、利用中の nixpkgs が同じ機能を提供したら標準パッケージへ戻す。

`src.hash` と `cargoHash` はリモートで確定するまで `lib.fakeHash` のままで、ビルド完了とは扱わない。既存の Niri 26.04 による構文検証と、固定 fork のビルド・構文検証を区別する。全画面透過の見た目も未確認で、固定版にない `fullscreen-backdrop-color` は出力しない。

Sunshine の起動ユーザーと通信経路の制限は [Tailscale の設計](tailscale.md#gui-の確認は-sunshine-と-moonlight-で行う) を参照。`output_name` で仮想出力を選ぶ。Sunshine のアプリの `output` はログの保存先なので画面選択には使えない（[Sunshine 2026.914.233613 の process.cpp](https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/process.cpp)、[wlgrab.cpp](https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/platform/linux/wlgrab.cpp)）。接続直前の出力生成と、配信アプリ終了時の削除が実際のキャプチャに反映されるかは実機で確かめる。
