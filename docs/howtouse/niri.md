# Niri を使う

設計: [セッションと画面配信](../architecture/niri.md)
関連: [GUI アプリ](gui-apps.md) / [キーの変換](keyboard-layers.md) / [外出先からの画面配信](tailscale.md)

固定 fork のハッシュ確定と Nix 評価・ビルド、実機適用は未確認です。以下は適用後の操作と確認手順です。

## ログインと操作

GDM で Niri を選んでログインします。`Mod` は Super キーです。

| キー | 操作 |
|---|---|
| `Mod+Return` | kitty を開く |
| `Super` 単押し / `Mod+D` | Quickshell スタートメニュー兼通知ハブを開く（安全策として `Mod+D` も併設） |
| `Mod+矢印` | 列・ウィンドウ・ワークスペースのフォーカスを動かす |
| `Mod+O` | Overview を切り替える |
| `Mod+F` / `Mod+Shift+F` | 列の最大化 / 全画面を切り替える |
| `Mod+V` | フローティングを切り替える |
| `Mod+Alt+V` | フローティングとタイルのフォーカスを行き来する |
| `Mod+Ctrl+V` | フローティングウィンドウを一括で隠す / 呼び戻す（一番下の動的ワークスペースへ退避） |
| `Mod+Alt+L` | 画面をロックする |
| `Mod+Escape` | アプリによるショートカットの抑止を切り替える |
| `Mod+Shift+Slash` | キー操作の一覧を開く |

常駐バーは置かず、普段は作業ウィンドウだけを表示します。`Super` 単押し（`keyd` が `F24` へ変換）または `Mod+D` で 2 カラムのスタートメニューが開き、`Tab` / `Shift+Tab` で画面上の全ボタン・スライダーへフォーカス移動できます（タブバーにフォーカスがある状態で `←` / `→` により `All` / `Windows` / `Files` / `Clipboard` / `Vault` / `Notify` を切替）。左カラムではプレフィックス（`@` Vault / `/` Files / `:` Clipboard / `?` Zen Browser Web 検索 / `=` 電卓）、右カラムでは時計・電池・ワークスペース・音量・明るさ・システムトレイ（`nm-applet` / `blueman-applet` / TwinDesk 等）・電源ボタン（ロック以外は 2 回クリック確認）を操作します。Bitwarden（`Vault`）の `~/.config/rbw/config.json` は `secrets/secrets.yaml` の `rbw_config` から `switch` 時に復号配置されるため、新しいマシンでは初回のみ `rbw register`（Bitwarden Web Vault の API キー登録）と `rbw sync` を実行してください。

## 設定を変更する

[個人の config.kdl](../../modules/home-manager/gui/niri/config.kdl) と [Quickshell ハブの QML](../../modules/home-manager/gui/quickshell/hub/) は、Home Manager がそのユーザーの checkout へ直接リンクします。編集は rebuild 前から作用します（QML は保存すると Quickshell が自動で再読み込みします）。まず `niri validate` でエラーを調べ、自動の再読み込みを確認します。必要なら `niri msg action load-config-file` で現在の設定を再読み込みします。

生成設定を変更する場合は [niri_config.star](../../config/elements/niri_config.star) と、変更したい機能の寄与元を編集し、リモートで検証してから構成を適用します。`~/.config/niri/generated.kdl` 自体は編集しません。キーを個人設定で上書きする場合は、include の後の `binds` に記述します。

Home Manager を使わない `mase` は `/etc/niri/config.kdl` と `/etc/xdg/quickshell/hub/` のシステム既定を使います。`~/.config/niri/config.kdl` がすでにある場合はそちらが優先されるので、システム既定へ戻す前にバックアップして移動します。checkout は不要です。

live symlink の誤編集は Git で該当ファイルを復元します。Nix 世代のロールバックでは復元されません。KDL が壊れて画面から直せない場合は、別の TTY または SSH で編集して `niri validate` を実行してください。

## 適用後に確認する

```sh
niri validate
niri msg outputs
niri msg windows
systemctl --user status niri.service quickshell-hub.service cliphist-watch.service swayidle.service
journalctl --user -b -u niri.service -u quickshell-hub.service -u cliphist-watch.service -u swayidle.service
```

`pomu` と `mase` の両方でログイン・ログアウトし、端末、スタートメニュー（`Super` 単押し・`Mod+D`・各タブ・`@` Bitwarden・`=` 電卓・`?` Web 検索）、通知ポップアップとクリック移動、トレイ、画面ロックと解錠、polkit 認証、Xwayland アプリを確認します。Home Manager の設定だけで確認を済ませず、`mase` が個人の checkout なしで使えることも確かめます。

spin713 ではタッチとペンの座標、回転、タブレットモード、ふた、明るさ・音量キー、サスペンドと復帰を確認します。`internal_output` の接続名は `niri msg outputs` と照合してください。自動回転のオン・オフはスタートメニューの「自動回転の切替」、自動回転をオフにしつつ時計回りに 90° 回転する操作は `Alt+更新キー`（`niri-rotate cw`）を使います。kitty の全画面透過、ブラウザの認証リダイレクト、画面共有、Windows VM の資格情報と右 Alt の操作も実機未確認です。

遠隔セッションの起動・停止とペアリングは [Tailscale](tailscale.md#外出先からデスクトップの画面を使うsunshine--moonlight) を参照してください。ローカルと headless を同じユーザーで同時に使わず、headless を止めてから GDM にログインします。
