# WebRTC エコーキャンセルの設計

使い方: [マイクへのスピーカーの音の回り込みを減らす](../howtouse/audio-echo-cancel.md)
実装: [call_audio.star](../../config/elements/call_audio.star)

## PipeWire の echo-cancel モジュールで既定の出力を参照する

スピーカーの音をマイクから除くため、既存の PipeWire に `libpipewire-module-echo-cancel` と `aec/libspa-aec-webrtc` を足す。
`monitor.mode = true` で既定の出力の monitor を参照する。アプリを仮想の出力に振り分ける方式より、動画、音楽、通話の音をまとめて参照しやすい。代わりに、既定以外の出力で同時に鳴らした音は参照されない。

- 入力はホストの `config/hosts/<ホスト>.toml` の `echo_cancel_source` で実マイクを指定する。仮想マイクを既定の入力にしても、AEC の入力が自分自身に向かないようにするため
- `node.dont-fallback = true` で、指定したマイクがないときに別の入力へつながるのを防ぐ
- `node.linger = true` で、起動時の USB 機器の列挙や再接続を待つ間にストリームが捨てられるのを防ぐ
- 仮想マイクは自動で選ばれる優先度を低くし、使うアプリが明示的に選ぶ
- 動いている間の入力と参照先は、`pwvucontrol` の標準の接続先の変更で切り替える。独自に選択を保存したり、switch のたびに初期のマイクに戻したりはしない
- 最初の比較でエコーの除去の効果を見やすくするため、WebRTC のノイズ除去と自動のゲイン調整は明示的に切る。既存の 48 kHz、低レイテンシの設定はそのままにし、処理のブロックの長さはライブラリに任せる

仕組みと型付きのオプションは NixOS の音声のモジュール、機器の名前と有効にすることは各ホストが持つ。既定は無効で、desktop と spin713 が有効にする。

## 確かめたことと、まだ確かめていないこと

- PipeWire 1.6.6 と WirePlumber 0.5.14 で、AEC のモジュールと WebRTC のライブラリがあることを確かめた（2026-10-03、両ホスト）
- desktop では、AEC の入力が SoloCast に、参照先が UR12 の monitor につながり、両方のストリームが PulseAudio 互換の録音ストリームとして見えた（2026-10-05）。`linking.allow-moving-streams` は有効だった。WirePlumber 0.5.14 の接続処理では、メタデータの `target.object` が起動時の指定より優先され、保存した接続先の復元はノードに `target.object` があると省かれる（[find-defined-target.lua](https://github.com/PipeWire/wireplumber/blob/0.5.14/src/scripts/linking/find-defined-target.lua)、[state-stream.lua](https://github.com/PipeWire/wireplumber/blob/0.5.14/src/scripts/node/state-stream.lua)）
- spin713 の内蔵の入力は AVS DMIC（2 チャンネル）、出力は AVS I2S MAX98357A だった。保存された既定の機器に Bluetooth の入出力の名前が残っていたので、つなぎ直した後の出力の選択は確かめる必要がある
- 接続の変更、録音、再起動後の復帰、実際の除去の性能、同時に話したときの音質、AEC の負荷、USB の再接続は確かめていない

monitor の参照で音質や同期に問題があれば、仮想の sink を経由する構成と比べる。
GUI での調整や追加の処理が要るなら EasyEffects を候補にする。DeepFilterNet や RNNoise は再生音を参照しないノイズ除去で、AEC とは役割が違うので置き換えない。

参考: [PipeWire の echo-cancel](https://docs.pipewire.org/page_module_echo_cancel.html)、[1.6.6 のモジュールの実装](https://github.com/PipeWire/pipewire/blob/1.6.6/src/modules/module-echo-cancel.c)（monitor のモードでは仮想の sink を作らず、入力のストリームが出力の monitor を参照する）、[WebRTC の実装](https://github.com/PipeWire/pipewire/blob/1.6.6/spa/plugins/aec/aec-webrtc.cpp)、[WirePlumber の接続のポリシー](https://pipewire.pages.freedesktop.org/wireplumber/policies/linking.html)
