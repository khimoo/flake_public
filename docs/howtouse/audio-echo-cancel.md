# マイクへのスピーカー音の回り込みを抑える（エコーキャンセル）

nixos-desktop および nixos-spin713 の PipeWire に、WebRTC ベースのエコーキャンセル（AEC）を設定している。デフォルトのスピーカー出力を参照し、その音声をマイク入力から取り除く。
処理後の仮想マイクは `Echo-Cancel Microphone`（node.name は `echo-cancel-source`）となり、AEC に入力する実マイクはホストごとの `config/hosts/<ホスト>.toml` の `echo_cancel_source` で指定する（desktop は HyperX SoloCast、spin713 は内蔵マイクの `alsa_input.platform-avs_dmic.19.auto.stereo-fallback`）。

設計: [WebRTC エコーキャンセルの設計](../architecture/audio-echo-cancel.md)
実装: [call_audio.star](../../config/elements/call_audio.star)

## 使い方

1. 設定適用後、一度ログアウトして再ログインする。すぐに反映させたい場合は、通話や録音を終了してから `systemctl --user restart pipewire pipewire-pulse wireplumber` を実行する（一時的に音声が途切れる）。
2. 通話・録音アプリの入力に `Echo-Cancel Microphone` を、出力に通常のスピーカーを選択する。

デフォルトの入力デバイスは実マイクのままになっているため、エコーキャンセルを行いたいアプリでのみ仮想マイクを選択する。実マイクに戻せば処理はバイパスされる。
アプリ自体にエコーキャンセル機能がある場合は、まずアプリ側をオフにして PipeWire の処理のみで音質を比較する。
ノイズ除去や自動ゲイン調整（AGC）はオフに設定している。音楽制作など、音声を加工したくない用途では実マイクを直接指定する。

## 動作確認

`wpctl status -n` を実行し、出力結果に `echo-cancel-source` が存在することを確認する。
`pwvucontrol` の「録音」タブ（「全ストリーム」表示に切り替え）または `qpwgraph` で、`echo-cancel-capture` がホストの実マイクに、`echo-cancel-reference` が現在使用中の出力の monitor に接続されていることを確認する。

実マイクと仮想マイクのそれぞれにおいて、「スピーカー音のみ」「自分の声のみ」「両方同時」の順で録音・比較し、スピーカー音の回り込みが低減され、かつ自分の声が途切れないか確認する。なお、録音した音声をリアルタイムでスピーカーから再生して確認しないこと（ハウリングの原因となるため）。
出力デバイスを切り替えた際も、参照先と録音状態を再確認する。spin713 では Bluetooth 機器の再接続時にデフォルト出力が変わることがあるため、内蔵スピーカーでテストする場合はそれをデフォルト出力に明示的に設定しておく。

仮想マイクが表示されない場合は `journalctl --user -u pipewire -b` でログを確認する。
指定した実マイクが存在しない場合、自動で他の入力へ切り替わることはなく、対象のマイクが認識されるまで待機する。
OS アップデート等で内蔵マイクの node.name が変更された場合は、`wpctl status -n` で名称を確認し、`config/hosts/<ホスト>.toml` の `echo_cancel_source` の設定を修正する。

## 入力デバイスの変更・無効化

動作中に接続先を変更する場合は `pwvucontrol` から変更可能で、設定ファイルの修正や PipeWire の再起動は不要。

1. 「録音」タブの表示設定を「全ストリーム」にする。
2. `Echo-Cancel Capture`（`echo-cancel-capture`）の入力元として、AEC を適用したい実マイクを選択する。`Echo-Cancel Microphone` 自身や出力の monitor は選択しないこと。
3. `Echo-Cancel Sink`（`echo-cancel-reference`）の入力元として、除去したい音が出力されている monitor を選択する。これは参照音の指定であり、スピーカーへの再生出力先は変更されない。アプリの再生先を変更する場合は「再生」タブで設定する。
4. アプリの入力設定を `Echo-Cancel Microphone` のままにし、選択した実マイクからの音声が正しく届いているか録音して確認する。

起動時に使用される実マイクは `config/hosts/<ホスト>.toml` の `echo_cancel_source` の設定に依存する。`wpctl status -n` で確認できる実マイクの node.name を記述し、仮想マイクや出力 monitor の名称は指定しないこと。
機能を無効化するには、desktop と spin713 のハードウェアプロファイルが `requires` に挙げる `personal_pc.star` の `requires` から `call_audio` を外して適用後、PipeWire を再起動する。
