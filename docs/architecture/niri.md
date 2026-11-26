# Niri のセッションと画面配信

使い方: [Niri](../howtouse/niri.md) / [外出先からの画面配信](../howtouse/tailscale.md)
実装: [desktop.star](../../config/elements/desktop.star) / [niri_config.star](../../config/elements/niri_config.star) / [niri_remote_session.star](../../config/elements/niri_remote_session.star)

## ログイン画面とアプリの共通サービスを残す

GDM をログイン画面に使い、ユーザーのセッションを Niri にする。GDM 自身が GNOME Shell などに依存するため、GNOME という名前のパッケージがクロージャにないことを受け入れ条件にしない。確認する境界は、GNOME のユーザーデスクトップ、拡張、GNOME Remote Desktop、独自 Mutter 置換が有効になっていないこと。

画面共有には `xdg-desktop-portal-gnome` と GTK portal、認証情報には GNOME Keyring を残す。固定した [nixpkgs の Niri モジュール](https://github.com/NixOS/nixpkgs/blob/e21fec321d73511849707a7585e4ea155ee4bf40/nixos/modules/programs/wayland/niri.nix) がこの組を選ぶ。Secret Service を使う [Windows VM](windows-vm.md) の資格情報も同じ保管先を使うが、Niri での解錠とブラウザ認証・画面共有は実機確認が要る。

## Home Manager の有無でセッションを分けない

Home Manager を使わない `mase` にも端末、スタートメニュー（ランチャー・通知・トレイ・電源）、ロックが必要なため、共通設定と常駐サービスは NixOS に置く。Quickshell ハブ（`quickshell-hub`）、`cliphist-watch`、`swayidle` はシステムが提供するユーザーユニットで起動し、Home Manager に同名のデーモンを作らない。`swaylock` には設定ファイルを明示して、パッケージの既定の探索先に依存させない。単機能 UI のコンポーネント定義（`waybar` / `swaync` / `vicinae`）は比較・ロールバック用に `config/elements/` へ残している。

個人の Niri と Quickshell ハブの設定だけを各ユーザーの checkout に live symlink で結ぶ。既存のユーザー設定はシステム既定より優先される。システム側にはユーザー名や checkout のパスを含めない。live symlink の変更は Nix 世代のロールバックでは戻らない（[構成の境界](configuration.md)）。

## KDL の寄与と手編集を分ける

生成するキー、XKB、環境変数などは `generated.kdl` にまとめ、設定の入口から include する。同じファイル内で `input` や `binds` を重複させるとエラーになるが、別ファイルの節は合成される。include の後のキー割り当ては、同じキーの生成設定より優先される。[Niri 26.04 の ConfigPart](https://github.com/niri-wm/niri/blob/8ed0da44d974c32c6877d2f4630c314da0717ecb/niri-config/src/lib.rs) がこの区別を実装する。

寄与同士の同一キーや、値が異なる環境変数は confgen で拒否する。生成成功だけでは KDL の正しさを保証できないため、[構文の check](../../tests/elements/niri.nix) は、寄与なし・デスクトップ一式・センサー付きの設定を Niri 自身で読む。

XDG Autostart は `xdg-desktop-autostart.target` に統一する。通常の `niri.service` と headless のユニットがこれを要求する。dex を追加すると二重起動になる。アプリを直接 systemd サービスにしない理由と背景ワークスペースは [既定アプリ](default-apps.md) を参照。

## 仮想出力のために fork を固定する

[パッケージ](../../packages/niri-virtual-outputs/default.nix) は PR [#3800](https://github.com/niri-wm/niri/pull/3800) の `willybarret/niri@7fd585dd44ed67644977dd9561bb6e8b3837f8f7` を固定する。nixpkgs の Niri 26.04 にそのまま当たらない差分であり、仮想出力と `NIRI_BACKEND=headless` を使うために必要となる。上流へ取り込まれ、利用中の nixpkgs が同じ機能を提供したら標準パッケージへ戻す。

`src.hash` と `cargoHash` はリモートで確定するまで `lib.fakeHash` のままで、ビルド完了とは扱わない。既存の Niri 26.04 による構文検証と、固定 fork のビルド・構文検証を区別する。全画面透過の見た目も未確認で、固定版にない `fullscreen-backdrop-color` は出力しない。

Sunshine の起動ユーザーと通信経路の制限は [Tailscale の設計](tailscale.md#gui-の確認は-sunshine-と-moonlight-で行う) を参照。`output_name` で仮想出力を選ぶ。Sunshine のアプリの `output` はログの保存先なので画面選択には使えない（[Sunshine 2026.914.233613 の process.cpp](https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/process.cpp)、[wlgrab.cpp](https://github.com/LizardByte/Sunshine/blob/v2026.914.233613/src/platform/linux/wlgrab.cpp)）。接続直前の出力生成と、配信アプリ終了時の削除が実際のキャプチャに反映されるかは実機で確かめる。
