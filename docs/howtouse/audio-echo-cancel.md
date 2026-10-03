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
AEC の入力は内蔵 DMIC に固定されています。ヘッドセットのマイクを使う場合はアプリでその実マイクを選びます。
OS 更新後などに内蔵マイクの node.name が変わった場合は、`wpctl status -n` で確認して `local.audio.echoCancel.source` を更新してください。

録音を実マイクと仮想マイクで比較します。スピーカーだけ、自分の声だけ、両方同時の順に試し、回り込みが減って自分の声が途切れないか確認してください。
録音した自分の声を同時にスピーカーへモニターしないでください。
出力を切り替えた場合も、参照先と録音結果を確認します。

仮想マイクが出ない場合は `journalctl --user -u pipewire -b` を確認します。
指定した実マイクが利用できない場合は他の入力へフォールバックせず、そのマイクが現れるまで待機します。

## 入力の変更・無効化

`wpctl status -n` に出る実マイクの node.name を、ホストの `local.audio.echoCancel.source` に設定します。
仮想マイクや出力の monitor を指定しないでください。
無効化するには `local.audio.echoCancel.enable = false;` に変更し、適用後に PipeWire を起動し直します。

ノイズ除去と自動ゲイン調整は無効にしています。ハイパスフィルターなどは WebRTC の既定値です。
音楽制作など、加工を避けたい用途には実マイクを選んでください。
Nix の評価・設定ファイルの生成確認だけでは、実際の除去性能や USB 再接続時の動作は保証できません。
