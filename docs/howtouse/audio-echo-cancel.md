# マイクへのスピーカー音の回り込みを減らす

設計: [WebRTC エコーキャンセル](../architecture/audio-echo-cancel.md)
実装: [音声モジュール](../../modules/nixos/audio.nix) / [デスクトップ設定](../../hosts/nixos-desktop/default.nix) / [spin713 設定](../../hosts/nixos-spin713/default.nix)

`nixos-desktop` と `nixos-spin713` に PipeWire の WebRTC エコーキャンセルを設定しています。
参照音は既定のスピーカー出力です。

| ホスト | AEC に渡す実マイク |
|---|---|
| `nixos-desktop` | HyperX SoloCast |
| `nixos-spin713` | 内蔵 AVS DMIC（`alsa_input.platform-avs_dmic.19.auto.stereo-fallback`） |

仮想マイクの名前は `Echo-Cancel Microphone`（node.name は `echo-cancel-source`）です。

## 適用と選択

1. 利用者が [README の手順](../../README.md)で対象ホストの設定を適用する。spin713 は [リモートビルド手順](./remote-build.md)を参照。
2. ログアウト・ログインしてユーザーの PipeWire を起動し直す。すぐに反映する場合は、通話・録音を終了してから `systemctl --user restart pipewire pipewire-pulse wireplumber` を実行する（音声が一時中断する）。
3. 通話・録音アプリの入力に `Echo-Cancel Microphone` を選ぶ。出力は通常のスピーカーを選ぶ。

既定の実マイクは維持します。処理を使いたいアプリで仮想マイクを選択してください。
通常のマイクへ戻すとエコーキャンセルを迂回できます。
アプリ内のエコーキャンセルを切れる場合は、まず PipeWire 側だけで比較してください。

## 確認

`wpctl status -n` で `echo-cancel-source` が表示されることを確認します。
`pavucontrol` の録音タブ（全ストリーム表示）または `qpwgraph` で、`echo-cancel-capture` がホストの指定マイクに、`echo-cancel-reference` が現在の出力の monitor に接続されていることを確認します。

spin713 は Bluetooth 機器を再接続すると既定の出力が変わる可能性があります。内蔵スピーカーで試す場合は、その出力を既定に選んでください。
AEC の初期入力は内蔵 DMIC です。別のマイクに AEC を適用する場合は、下記の `pavucontrol` で入力元を変更します。処理を迂回する場合はアプリで実マイクを選びます。
OS 更新後などに内蔵マイクの node.name が変わった場合は、`wpctl status -n` で確認して `local.audio.echoCancel.source` を更新してください。

録音を実マイクと仮想マイクで比較します。スピーカーだけ、自分の声だけ、両方同時の順に試し、回り込みが減って自分の声が途切れないか確認してください。
録音した自分の声を同時にスピーカーへモニターしないでください。
出力を切り替えた場合も、参照先と録音結果を確認します。

仮想マイクが出ない場合は `journalctl --user -u pipewire -b` を確認します。
指定した実マイクが利用できない場合は他の入力へフォールバックせず、そのマイクが現れるまで待機します。

## 入力の変更・無効化

実行中の接続先は `pavucontrol` で変更できます。`nixos-rebuild` や PipeWire の再起動は不要です。

1. 録音タブの表示を「全ストリーム」にします。
2. `Echo-Cancel Capture`（`echo-cancel-capture`）の入力元に、AEC を適用したい実マイクを選びます。`Echo-Cancel Microphone` 自身や出力の monitor は選ばないでください。
3. `Echo-Cancel Sink`（`echo-cancel-reference`）の入力元には、除去したい再生音が出ている出力デバイスの monitor を選びます。これは再生音の参照先であり、スピーカーへの再生先を変更する操作ではありません。アプリの再生先は再生タブで変更します。
4. アプリの入力は `Echo-Cancel Microphone` のままにし、選んだ実マイクの音が届くことを録音などで確認します。

以下の Nix 設定は起動時の初期入力を指定します。実行中の切り替えとは別です。
`wpctl status -n` に出る実マイクの node.name を、ホストの `local.audio.echoCancel.source` に設定します。
仮想マイクや出力の monitor を指定しないでください。
無効化するには `local.audio.echoCancel.enable = false;` に変更し、適用後に PipeWire を起動し直します。

ノイズ除去と自動ゲイン調整は無効にしています。ハイパスフィルターなどは WebRTC の既定値です。
音楽制作など、加工を避けたい用途には実マイクを選んでください。
Nix の評価・設定ファイルの生成確認だけでは、実際の除去性能や USB 再接続時の動作は保証できません。

## GNOME のマイク使用表示

GNOME 50 の環境には Mic Indicator Visibility Manager を導入します。
AEC の内部録音ストリームが常駐するため、通話・録音アプリが入力を使っていなくても、再生中などに標準のマイク使用表示が点灯します。
拡張は内部ストリーム `echo-cancel-capture` と `echo-cancel-reference` だけを除外します。
仮想入力全般は隠さず、アプリが `Echo-Cancel Microphone` を使う場合はマイク使用を表示します。
GNOME Shell の private API に依存し、取得・解析などの失敗時は標準表示に戻ります。対応版と修正の根拠は [設計](../architecture/audio-echo-cancel.md#gnome-のマイク使用表示)を参照してください。

利用者が [README の rebuild 手順](../../README.md)で対象ホストへ適用し、ログアウト・ログインして拡張を読み込みます。
修正版の反映にもログアウト・ログインが必要です。読み込み状態は次で確認し、`Enabled: Yes` と `State: ACTIVE` になっていることを確認します。

```sh
gnome-extensions info mic-indicator-visibility-manager@alhaddar.dev
```

`State: ERROR` の場合は、`journalctl --user -b --no-pager | rg 'mic-indicator|Mic indicator'` で関連する起動エラーを確認します。初版には表示オブジェクトの生成前に起動すると失敗する競合があり、修正版は生成後の初期化に合わせて処理を取り付けます。

表示の調整を無効化する場合は、GNOME の「拡張機能」で Mic Indicator Visibility Manager をオフにするか、次を実行します。

```sh
gnome-extensions disable mic-indicator-visibility-manager@alhaddar.dev
```

これで標準の表示へ戻ります。宣言設定では拡張を有効にしているため、設定の再適用で有効に戻る場合があります。

修正版の適用後、利用者から動作しているように見えるとの報告がありました。表示の各条件は次の手順で手動確認できます。

1. 通話・録音アプリを終了し、AEC の内部ストリームだけが動いている間はマイク使用表示が出ないこと。
2. 通話・録音アプリで `Echo-Cancel Microphone` を選び、入力を使っている間は表示が出ること。
3. アプリが入力の使用を終了すると表示が消えること。
4. 拡張を無効化すると、AEC の内部ストリームによる標準のマイク使用表示が復帰すること。
