# キーボードレイヤーの確認手順

修飾キーを押した際に各キーがどのように動作するかを確認する手順です。

HID の入力形式、keyd のキーコード変換、Niri の XKB とショートカット、アプリの割り当てを順に確認します。XKB の配列だけを調べても keyd の変換は分かりません。

## 入力が届く順序

| 層 | 担当役割 | 設定場所 | 調査用ツール |
|----|------|------|-----------|
| HID | 機器の申告を Linux のキー入力に変換。HHKB-BT の音量キーは HID-BPF で申告を補正 | [HHKB-BT 補正](../../packages/hhkb-bt-audio/) | HID の生レポートと evdev の比較 |
| keyd | evdev レベルのキーコード変換 | `/etc/keyd/*.conf`（[keyd.star](../../config/elements/keyd.star) が集約） | `keyd monitor`, `keyd listen` |
| xkb | レイアウトとシフトレベル（Shift / AltGr） | [xkb.star](../../config/elements/xkb.star) を正本とし、Niri（`generated.kdl`）と GDM（`services.xserver.xkb`）の両方が参照 | `xkbcli compile-keymap`, `xkbcli interactive-wayland` |
| コンポジタ / アプリ | Niri のショートカット、IME（fcitx5）、各アプリケーション | [config.kdl](../../modules/home-manager/gui/niri/config.kdl)、各アプリケーションの設定 | Niri の `Mod+?`、各アプリケーションの設定画面 |

keyd は物理キーボードの入力を直接キャッチし、変換後のキーコードを `keyd virtual keyboard` という仮想デバイスとしてシステムへ流し直します。
xkb に届くのは変換済みの結果のみであるため、XKB の配列図には keyd による変換内容は反映されません。

XKB の既定配列 `us+altgr-intl` は [xkb.star](../../config/elements/xkb.star) が `layout = "us"` と `variant = "altgr-intl"` に分け、[niri_config.star](../../config/elements/niri_config.star)（`generated.kdl`）と [gdm.star](../../config/elements/gdm.star)（ログイン画面）へ供給します。右 Alt が AltGr になる配列です。例外ホストで配列を変える場合のみ [ホストの TOML](../../config/hosts/) に `xkb_layout` を指定します。コンポジタの割り当てと反映方法は [Niri](niri.md) を参照してください。

例として、spin713 では Alt+Backspace で Delete が入力されますが、xkb 側にはその定義は存在しません。`/etc/keyd/internal.conf` の `[alt]` セクションに記述された `backspace=delete` が実際の挙動を定義しています。

Meltype の日本語と英数は、spin713 の内蔵キーボードでも HHKB などの外付けでも **左 Alt+Space** で切り替えます（[ime_toggle_key.star](../../config/elements/ime_toggle_key.star)）。Caps Lock は大文字固定のまま、右 Alt（AltGr）はアクセント入力のままです。

## HHKB Professional BT の音量キー

Mac モードで使用します。本体の電源を切り、SW1 を OFF、SW2 を ON にしてから電源を入れ直します。

| キー | 操作 |
|---|---|
| `Fn+A` | 音量を 5% 下げる |
| `Fn+S` | 音量を 5% 上げる（上限 100%） |
| `Fn+D` | ミュートを切り替える |

`audio_controls` は接続時に `udev-hid-bpf` を呼び、Bluetooth の HHKB-BT（`04fe:0202`）に補正を付けます。再接続・再起動後も適用されます。操作後の値は `wpctl get-volume @DEFAULT_AUDIO_SINK@` で確認できます。接続時の補正エラーは `journalctl -b -u systemd-udevd --grep 'hid-bpf|HHKB'` で調べます。

本体が公開する 315 バイトの HID 記述子は、音量キーを含む Report ID 2 を Constant と宣言しています。[Linux 6.18.63 の HID 入力処理](https://github.com/gregkh/linux/blob/v6.18.63/drivers/hid/hid-input.c) は Constant のフィールドを入力として扱わないため、Niri のキー割当まで届きません。補正は音量とミュートの 3 ビットだけを Data にし、本体が送るビット位置と他のレポートを保持します。入力形式が一致しない機器には補正しません。

本体または上流の Linux が音量キーを正しく扱うようになったら、`audio_controls` の `services.udev.packages` からこの補正を外せます。

## 画面の明るさキー

明るさキーは `0% → 3% → 5% → 10% → 15% → … → 100%` の段階で移動します。ハブのスライダーなどで段階の間に設定した場合も、キーを押した方向にある最も近い段階に移ります。0% で画面が真っ暗になったら、明るさを上げるキーを押すと 3% に戻ります。段階を変えるには [audio_controls.star](../../config/elements/audio_controls.star) の `percent` の並びを編集します。

## keyd の設定ファイルの読み方

`/etc/keyd/*.conf` はレイヤーごとにセクション分けされているため、そのままマッピングの一覧として確認できます。

```
[main]
f1=back              単体の F1 は「戻る」（ChromeOS の最上段キーを再現）

[meta]
f1=f1                検索キー + F1 で本来のファンクションキーとして動作

[alt]
backspace=delete     Alt+Backspace で Delete
```

設定の生成元は以下のとおりです。共通の既定キーボード（`default.conf`、左右 Super 単押し→`F24`）は [keyd.star](../../config/elements/keyd.star) が持ち、ホスト固有の差分だけを各マシン定義から寄与します。

| 対象 | 設定ファイル | 内容 |
|--------|---------|------|
| 全ホスト共通（既定） | [keyd.star](../../config/elements/keyd.star) | `default.conf`（`leftmeta` / `rightmeta` 単押し→`F24`、`quickshell_hub` が `super_tap_key` を参照） |
| nixos-spin713 | [machine_nixos_spin713.star](../../config/elements/machine_nixos_spin713.star) / [nixos-spin713.toml](../../config/hosts/nixos-spin713.toml) | 内蔵キーボード（`internal.conf`：ChromeOS 配列の再現＋Super 単押し→`F24`）を寄与し、`default.conf` から内蔵 ID を除外 |
| nixos-desktop | [machine_nixos_desktop.star](../../config/elements/machine_nixos_desktop.star) | `default.conf` へ右 Alt による右クリック連打レイヤー（`◇ + 右 Alt` でオン/オフ切替、起動時はオフ）を寄与 |

## 設定に書かれていないキーの挙動

暗黙的な上書きは行われません。設定に現れないキーはそのまま通過します。
keyd は `main` レイヤーで各キーを自分自身にバインドしているため、未指定のキーは素通しになります。

`[alt]` や `[control]` は keyd の組み込みレイヤーであり、内部的には `alt:A` のように修飾キー付きで定義されています。
明示的なマッピングがないキーについては単にその修飾キーを付与して出力するだけなので、`Alt+j` などは設定に記述がなくてもそのまま `Alt+j` として入力されます。

注意が必要なのは、むしろ明示的に記述されているキーの副作用です。以下の 3 点は直感に反しやすいため留意してください。

**レイヤー内のバインディングは、そのレイヤー自身の修飾キーを受け取らない**
`[alt]` セクション内の `backspace=delete` が出力するのは、Alt+Delete ではなく単体の Delete です。Ctrl+Alt+Backspace で Ctrl+Alt+Delete を出力するために、`[controlalt]` セクションに `backspace = "C-A-delete"` と修飾キーを明示的に指定しているのはこのためです。

**レイヤーは物理キー名で参照され、上位レイヤーが `main` を隠蔽する**
`[main]` に書かれた `f1=back` は、Meta キーの押下中には参照されず、`[meta]` の `f1=f1` が優先されます。ここで `[meta]` の `f1` が指しているのは物理的な F1 キーであり、`main` で変換された後の `back` ではありません。

**`[ids]` に記載のないデバイスは keyd を通過しない**
spin713 では内蔵キーボードの ChromeOS リマップ（`internal.conf`）と、それ以外の外付けキーボード向けの既定設定（`default.conf`、`*` から内蔵 ID を除外）を分けているため、外付けキーボードでは配列を崩さず Super 単押しだけが効きます。

## 実際のイベントを確認する

`keyd monitor` で変換前後のキーイベントを、`keyd listen` でアクティブなレイヤーの遷移を確認できます。evdev の読み取りには root 権限が必要です。

```sh
# keyd の実行ファイルパスを取得（世代を切り替えると変更されます）
systemctl cat keyd | grep ExecStart

pkexec /run/current-system/sw/bin/bash -c '<上で取得したパス> monitor'
```

`services.keyd` は keyd を `environment.systemPackages` に追加しないため、標準では PATH が通っていません。日常的にコマンドを利用する場合は、`pkgs.keyd` を追加してください。

xkb 側のシフトレベル（段）を一覧表示したい場合は、以下を実行します。
出力は `[ 素, Shift, AltGr, AltGr+Shift ]` の順に並びます。

```sh
nix shell nixpkgs#libxkbcommon -c xkbcli compile-keymap --layout us --variant altgr-intl | grep 'key <'
```

キーを押した瞬間の最終的な解決結果（keyd 変換後の keysym および修飾キーの状態）を確認するには、`xkbcli interactive-wayland` を使用します。

## 設定を誤って入力不能になった場合の復旧

keyd は物理入力デバイスを直接制御するため、設定を誤るとログインすらできなくなる可能性があります。
その場合は、`backspace` + `escape` + `enter` を同時に押してください。これが緊急脱出用のパニックシーケンスとなっており、keyd を強制終了して通常の素のキーボード状態へ復帰させることができます。
