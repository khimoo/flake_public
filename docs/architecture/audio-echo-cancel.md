# PipeWire の WebRTC エコーキャンセル

使い方: [マイクへのスピーカー音の回り込みを減らす](../howtouse/audio-echo-cancel.md)
実装: [音声モジュール](../../modules/nixos/audio.nix) / [デスクトップ設定](../../hosts/nixos-desktop/default.nix) / [spin713 設定](../../hosts/nixos-spin713/default.nix)

## 判断

スピーカー再生音をマイクから除くため、既存の PipeWire に `libpipewire-module-echo-cancel` と `aec/libspa-aec-webrtc` を追加する。
`monitor.mode = true` で既定の出力の monitor を参照する。仮想出力へアプリを振り分ける方式より、動画・音楽・通話の再生音を共通に参照しやすい。
複数の出力へ同時に再生する場合、既定の出力以外の音は参照対象にならない。

入力はホストの `local.audio.echoCancel.source` で物理マイクを指定する。
仮想マイクを既定入力に選んでも AEC の入力が自分自身に向かないようにするためである。
`node.dont-fallback = true` で指定マイク不在時の別入力への接続を防ぐ。
`node.linger = true` で起動時の USB 機器の列挙待ちや再接続待ちにストリームが破棄されるのを防ぐ。
仮想マイクの自動選択優先度は低くし、利用アプリが明示的に選択する。
出力デバイスの選択は通常の PipeWire / WirePlumber に任せる。

仕組みと型付きオプションは NixOS の音声モジュール、機器名と有効化は各ホストが所有する。
オプションの既定値は無効で、デスクトップと spin713 が明示的に有効にする。
既存の 48 kHz・低レイテンシー設定は維持し、AEC の処理ブロック長はライブラリに任せる。
最初の比較ではエコー除去の効果を見やすくするため、WebRTC のノイズ除去と自動ゲイン調整を明示的に無効にする。

## 根拠と未確認事項

2026-10-03 に対象構成と稼働中の PipeWire が 1.6.6 であること、対象パッケージに AEC モジュールと WebRTC ライブラリが含まれることを確認した。
稼働デバイス一覧では既定入力が HyperX SoloCast、既定出力が Steinberg UR12 だった。

同日に spin713 へ SSH で読み取り調査した。PipeWire 1.6.6 / WirePlumber 0.5.14 が稼働し、AEC モジュールと WebRTC ライブラリが存在した。
内蔵入力は AVS DMIC（2 チャンネル、`alsa_input.platform-avs_dmic.19.auto.stereo-fallback`）、内蔵出力は AVS I2S MAX98357A（`alsa_output.platform-avs_max98357a.20.auto.stereo-fallback`）だった。
調査時は両者が既定として表示され、ミュートされていなかった。ただし保存済みの既定機器には Bluetooth の入出力名が残っていたので、再接続後の出力選択は確認が必要。
録音・再生・サービス再起動は行っておらず、実マイクの収音品質や AEC の負荷・除去性能は未測定。
既存の Chromebook UCM 上書きと旧 Lua 設定は今回変更せず、実機で列挙された DMIC を使う。

- [PipeWire 公式説明](https://docs.pipewire.org/page_module_echo_cancel.html): 仮想 source、再生音参照、monitor.mode の役割。
- [1.6.6 のモジュール実装](https://github.com/PipeWire/pipewire/blob/1.6.6/src/modules/module-echo-cancel.c): monitor モードでは仮想 sink / playback を作らず、入力ストリームが出力 monitor を参照する。
- [1.6.6 の WebRTC 実装](https://github.com/PipeWire/pipewire/blob/1.6.6/spa/plugins/aec/aec-webrtc.cpp): AEC の有効化、ノイズ除去・ゲイン調整の引数と 10 ms 単位の処理。
- [WirePlumber の接続ポリシー](https://pipewire.pages.freedesktop.org/wireplumber/policies/linking.html): target.object、node.dont-fallback、node.linger の役割。

EasyEffects は GUI 調整や追加処理が必要になった場合の候補。
DeepFilterNet / RNNoise の通常のノイズ除去は再生音参照を使う AEC と役割が異なるので、今回の置き換えにはしない。
実際の除去性能、同時発話時の音質、出力変更・USB 再接続は利用者の環境で確認が必要。
monitor 参照で音質や同期に問題があれば、仮想 sink 経由の構成を比較する。
