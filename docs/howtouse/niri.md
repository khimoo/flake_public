# Niri を使う

設計: [セッションと画面配信](../architecture/niri.md)
関連: [GUI アプリ](gui-apps.md) / [キーの変換](keyboard-layers.md) / [外出先からの画面配信](tailscale.md)

固定 fork のハッシュ確定と Nix 評価・ビルド、実機適用は未確認です。以下は適用後の操作と確認手順です。

## ログインと操作

GDM で Niri を選んでログインします。`Mod` は Super キーです。

| キー | 操作 |
|---|---|
| `Mod+Return` | 端末（kitty）を開く。開く端末は [terminal_exec.star](../../config/elements/terminal_exec.star) が `xdg-terminal-exec` の設定として決める |
| `Super` 単押し / `Mod+D` | Quickshell スタートメニュー兼通知ハブを開く（安全策として `Mod+D` も併設） |
| `Mod+H/J/K/L` | モニター内のフォーカスを動かす（左右＝列、上下＝列内ウィンドウ / ワークスペース） |
| `Mod+Shift+H/J/K/L` | モニター内でウィンドウ・列を動かす（左右＝列の並び替え、上下＝列内移動 / ワークスペース移動） |
| `Mod+Ctrl+H/J/K/L` | モニター間でフォーカスを動かす |
| `Mod+Ctrl+Shift+H/J/K/L` | モニター間でウィンドウを運ぶ |
| `Mod+O` | Overview を切り替える |
| `Mod+R` / `Mod+Shift+R` / `Mod+C` | 列幅のプリセット切替 / ウィンドウ高さのプリセット切替 / 列を中央寄せ |
| `Mod+Minus` / `Mod+Equal` | 列幅を -10% / +10% 調整する |
| `Mod+Shift+Minus` / `Mod+Shift+Equal` | ウィンドウ高さを -10% / +10% 調整する |
| `Mod+F` / `Mod+Shift+F` | 列の最大化 / 全画面を切り替える |
| `Mod+[` / `Mod+]` / `Mod+W` | 左/右の列へ縦積み・追い出し / 列のタブ表示切替 |
| `Mod+V` / `Mod+Alt+V` | フローティング切替 / タイルとフローティング間のフォーカス移動 |
| `Mod+Ctrl+V` | フローティングウィンドウを一括で隠す / 呼び戻す（一番下の動的ワークスペースへ退避） |
| `Mod+Shift+S` / `Mod+Ctrl+S` / `Mod+Alt+S` | 範囲 / 画面全体 / ウィンドウのスクリーンショット（`Print` 系も互換として併設） |
| `Mod+Alt+L` | 画面をロックする |
| `Mod+Escape` | アプリによるショートカットの抑止を切り替える |
| `Mod+Shift+Slash` | キー操作の一覧を開く |

常駐バーは置かず、普段は作業ウィンドウだけを表示します。`Super` 単押し（`keyd` が `F24` へ変換）または `Mod+D` で 2 カラムのスタートメニューが開き、`Tab` / `Shift+Tab` で画面上の全ボタン・スライダーへフォーカス移動できます（タブバーにフォーカスがある状態で `←` / `→` により `All` / `Windows` / `Files` / `Clipboard` / `Vault` / `Notify` を切替）。左カラムではプレフィックス（`@` Vault / `/` Files / `:` Clipboard / `?` Zen Browser Web 検索 / `=` 電卓）、右カラムでは時計・電池・ワークスペース・ディスプレイ配置・音量・明るさ・システムトレイ（`nm-applet` / `blueman-applet` / TwinDesk 等）・電源ボタン（ロック以外は 2 回クリック確認）を操作します。Bitwarden（`Vault`）の `~/.config/rbw/config.json` は `secrets/secrets.yaml` の `rbw_config` から `switch` 時に復号配置されるため、新しいマシンでは初回のみ `rbw register`（Bitwarden Web Vault の API キー登録）と `rbw sync` を実行してください。`Files` は `~/.config/user-dirs.dirs` に登録されたホーム配下のフォルダ（デスクトップ・ダウンロード・ドキュメント・画像など）だけを検索し、ホーム直下やその他のフォルダは対象にしません。`.desktop` に `Terminal=true` と書かれたアプリ（yazi・btop など）は、`xdg-terminal-exec` が開く端末（kitty）の中で起動します。

## 次のログインでウィンドウを復元する

`nixos-desktop` で [restore_desktop_session](../../config/elements/restore_desktop_session.star) を選んだユーザーには、ローカルの Niri ログインで `nirinit` が動きます。ウィンドウのワークスペースとサイズを30秒おきに保存し、次のログインで開き直します。ログアウト直前に強制保存はしないので、最後の保存以降の変更は戻りません。ブラウザーのタブや端末で実行中のコマンドは `nirinit` の保存対象ではありません。復元時は設定またはインストール済みの `.desktop` から起動コマンドを探します。

ログイン時は、標準版の `nirinit` を起動する前に `session.json` を読みます。付箋と Thunderbird のうち、保存にないアプリだけ通常どおり開き、保存にあるアプリの起動と配置は `nirinit` に任せます。保存にあるアプリの復元が失敗しても自動では起動し直しません。Discord・Slack などのトレイ／最小化用自動起動は従来どおりです。headless セッションでは `nirinit` を起動せず、付箋と Thunderbird も従来の自動起動を使います。

`journalctl --user -b -u nirinit.service` で復元と起動のログを確認できます。前回の配置を破棄するときは、ログイン中の定期保存でファイルが作り直されないよう `systemctl --user stop nirinit.service` を実行してから `${XDG_DATA_HOME:-$HOME/.local/share}/nirinit/session.json` を削除します。

## 設定を変更する

[ホームの config.kdl](../../modules/home-manager/gui/niri/config.kdl) と [Quickshell ハブの QML](../../modules/home-manager/gui/quickshell/hub/) は、既定で Nix store を参照します。rebuild なしで編集・反映したいときは、スタートメニュー右カラムの [Dev モード](dotfiles-mode.md)（または `dotfiles-mode toggle niri` / `dotfiles-mode toggle quickshell`）を ON にしてローカル checkout へ切り替えます。まず `niri validate` でエラーを調べ、必要なら `niri msg action load-config-file` で現在の設定を再読み込みします。`switch` や `flake-deploy` を実行すると自動的に Nix store へ戻ります。

XKB・環境変数・各機能コンポーネントの寄与（Quickshell ハブ、画面ロック、音量・明るさ、フローティング一括退避、2-in-1 画面回転など）は [niri_config.star](../../config/elements/niri_config.star) が `~/.config/niri/generated.kdl` に生成します。これらを変更する場合は対応するコンポーネントを編集し、リモートで検証してから構成を適用します。`~/.config/niri/generated.kdl` 自体は編集しません。

Niri の設定ファイルは Home Manager 側で管理します（`/etc/niri/` のシステム既定は置きません）。別ユーザーで Niri を使う場合は、そのユーザーの Home Manager 構成を有効にします。

Dev モード ON 中の誤編集は Git で該当ファイルを復元するか、`dotfiles-mode off niri` で Nix store へ戻します。KDL が壊れて画面から直せない場合は、別の TTY または SSH で `dotfiles-mode off niri` または `niri validate` を実行してください。

## ディスプレイ配置を GUI で管理する

普段の切替は、スタートメニュー（`Super` 単押し / `Mod+D`）右カラムの **「ディスプレイ」** 欄にあるプロファイルボタンをクリック（または `Tab` → `Enter`）するだけで `kanshictl switch` が実行されます。

プロファイルの追加・個別編集・削除は、まずスタートメニュー右カラムの [Dev モード](dotfiles-mode.md) で **`kanshi` を ON** にしてから、右カラムの **「管理」** ボタン（またはスタートメニューの「ディスプレイ配置の切替 (kanshi)」／端末の `kanshi-switch`）で `fuzzel` ランチャーを開いて行います（OFF のままでも既存プロファイルの切替は可能です）：

- **新規プロファイルを作成（`kanshi-switch --create`）**: プロファイル名を入力すると `wdisplays` が開きます。画面の ON/OFF・配置・倍率を調整して **Apply** し、`wdisplays` を閉じると [modules/home-manager/gui/kanshi/config](../../modules/home-manager/gui/kanshi/config) に名前付き `profile` として追記され、自動で再読み込み・切替されます。
- **起動時の既定を変更（`kanshi-switch --set-default`）**: 選んだプロファイルを `kanshi/config` の先頭へ移動し、ログイン・再起動時の既定にします（複数プロファイルがあるとき、既定のボタンには `★` が付きます）。
- **既存プロファイルを編集（`kanshi-switch --edit`）**: 対象プロファイルを選んで `wdisplays` で調整し、**Apply** → ウィンドウを閉じると、そのプロファイルのブロックだけを差し替えます（同じモニター構成で複数パターンがある場合でも他のプロファイルを壊しません）。
- **プロファイルを削除（`kanshi-switch --delete`）**: 選択したプロファイルを `kanshi/config` から削除し、再読み込みします。
- **一時調整・保存なし（`wdisplays --no-kanshi`）**: 設定ファイルを変更せずにその場だけ試します。

運用上の注意点：

- GUI で作成・編集・削除した差分は `git diff modules/home-manager/gui/kanshi/config` で確認し、確定したらコミットします。コミット後に他ホストで `pull` / `switch` すると、同じ設定が共有されます（`mase` 向けの `/etc/kanshi/config` にも次の `switch` で反映されます）。
- 同じモニター構成のプロファイルが複数ある場合、ファイル内で**一番上にあるもの**が起動時・再接続時の既定になります。
- GUI で誤った変更を保存した場合は `git checkout -- modules/home-manager/gui/kanshi/config` で戻し、`kanshictl reload`（またはランチャーの「再読み込み」）を実行します。
- [個人の config.kdl](../../modules/home-manager/gui/niri/config.kdl) に同じ出力の `output` ブロック（例: `output "eDP-1"`）があると起動時・リロード時に `kanshi` と競合する可能性があるため、該当出力を `kanshi` 側へ移したら `config.kdl` 側の重複記述は整理してください。

## 適用後に確認する

```sh
niri validate
niri msg outputs
niri msg windows
systemctl --user status niri.service quickshell-hub.service cliphist-watch.service swayidle.service kanshi.service
journalctl --user -b -u niri.service -u quickshell-hub.service -u cliphist-watch.service -u swayidle.service -u kanshi.service
```

ログイン・ログアウトし、端末、スタートメニュー（`Super` 単押し・`Mod+D`・各タブ・`@` Bitwarden・`=` 電卓・`?` Web 検索）、通知ポップアップとクリック移動、トレイ、画面ロックと解錠、polkit 認証、Xwayland アプリを確認します。

spin713 ではタッチとペンの座標、回転、タブレットモード、ふた、明るさ・音量キー、サスペンドと復帰を確認します。`internal_output` の接続名は `niri msg outputs` と照合してください。自動回転のオン・オフはスタートメニューの「自動回転の切替」、自動回転をオフにしつつ時計回りに 90° 回転する操作は `Alt+更新キー`（`niri-rotate cw`）を使います。kitty の全画面透過、ブラウザの認証リダイレクト、画面共有、Windows VM の資格情報と右 Alt の操作も実機未確認です。

遠隔セッションの起動・停止とペアリングは [Tailscale](tailscale.md#外出先からデスクトップの画面を使うsunshine--moonlight) を参照してください。ローカルと headless を同じユーザーで同時に使わず、headless を止めてから GDM にログインします。
