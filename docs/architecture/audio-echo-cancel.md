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

実行中の入力と再生音参照は、`pavucontrol` の録音タブから標準の接続先変更機能で切り替える。独自の選択保存・復元や、`nixos-rebuild switch` ごとの初期マイクへのリセットは追加しない。操作手順は上記の使い方に記載する。

仕組みと型付きオプションは NixOS の音声モジュール、機器名と有効化は各ホストが所有する。
オプションの既定値は無効で、デスクトップと spin713 が明示的に有効にする。
既存の 48 kHz・低レイテンシー設定は維持し、AEC の処理ブロック長はライブラリに任せる。
最初の比較ではエコー除去の効果を見やすくするため、WebRTC のノイズ除去と自動ゲイン調整を明示的に無効にする。

## 根拠と未確認事項

2026-10-03 に対象構成と稼働中の PipeWire が 1.6.6 であること、対象パッケージに AEC モジュールと WebRTC ライブラリが含まれることを確認した。
稼働デバイス一覧では既定入力が HyperX SoloCast、既定出力が Steinberg UR12 だった。

2026-10-05 にデスクトップの PipeWire 1.6.6 / WirePlumber 0.5.14 を読み取り確認した。AEC 入力は SoloCast、再生音参照は UR12 の monitor に接続され、両ストリームは PulseAudio 互換の録音ストリームとして公開されていた。`linking.allow-moving-streams` は有効だった。採用版の接続処理ではメタデータの `target.object` が起動時の指定より優先される。一方、保存済み接続先の復元処理はノードに `target.object` がある場合に復元を省略する。接続変更・録音・再起動後の復帰はこの調査では未検証。

2026-10-03 に spin713 へ SSH で読み取り調査した。PipeWire 1.6.6 / WirePlumber 0.5.14 が稼働し、AEC モジュールと WebRTC ライブラリが存在した。
内蔵入力は AVS DMIC（2 チャンネル、`alsa_input.platform-avs_dmic.19.auto.stereo-fallback`）、内蔵出力は AVS I2S MAX98357A（`alsa_output.platform-avs_max98357a.20.auto.stereo-fallback`）だった。
調査時は両者が既定として表示され、ミュートされていなかった。ただし保存済みの既定機器には Bluetooth の入出力名が残っていたので、再接続後の出力選択は確認が必要。
録音・再生・サービス再起動は行っておらず、実マイクの収音品質や AEC の負荷・除去性能は未測定。
既存の Chromebook UCM 上書きと旧 Lua 設定は今回変更せず、実機で列挙された DMIC を使う。

- [PipeWire 公式説明](https://docs.pipewire.org/page_module_echo_cancel.html): 仮想 source、再生音参照、monitor.mode の役割。
- [1.6.6 のモジュール実装](https://github.com/PipeWire/pipewire/blob/1.6.6/src/modules/module-echo-cancel.c): monitor モードでは仮想 sink / playback を作らず、入力ストリームが出力 monitor を参照する。
- [1.6.6 の WebRTC 実装](https://github.com/PipeWire/pipewire/blob/1.6.6/spa/plugins/aec/aec-webrtc.cpp): AEC の有効化、ノイズ除去・ゲイン調整の引数と 10 ms 単位の処理。
- [WirePlumber の接続ポリシー](https://pipewire.pages.freedesktop.org/wireplumber/policies/linking.html): target.object、node.dont-fallback、node.linger の役割。
- [WirePlumber 0.5.14 の接続先選択](https://github.com/PipeWire/wireplumber/blob/0.5.14/src/scripts/linking/find-defined-target.lua) / [保存・復元処理](https://github.com/PipeWire/wireplumber/blob/0.5.14/src/scripts/node/state-stream.lua): 実行中の接続先変更と起動時の指定の優先関係。

EasyEffects は GUI 調整や追加処理が必要になった場合の候補。
DeepFilterNet / RNNoise の通常のノイズ除去は再生音参照を使う AEC と役割が異なるので、今回の置き換えにはしない。
実際の除去性能、同時発話時の音質、出力変更・USB 再接続は利用者の環境で確認が必要。
monitor 参照で音質や同期に問題があれば、仮想 sink 経由の構成を比較する。

## GNOME のマイク使用表示

AEC の内部録音ストリームが常駐するため、通話・録音アプリが入力を使っていなくても、再生中などに GNOME のマイク使用表示が点灯する。
[GNOME の Home Manager 設定](../../modules/home-manager/gui/gnome.nix)で、GNOME を利用するすべてのユーザーに Mic Indicator Visibility Manager を導入する。
`ignored-properties` は `node.name:echo-cancel-capture` と `node.name:echo-cancel-reference` の2つだけにし、`show-virtual-sources = true` とする。
仮想入力全般は隠さず、通話・録音アプリによる `Echo-Cancel Microphone` の利用は表示する。`application.id` を偽装して標準表示を抑制する方法は使わない。

[パッケージ定義](../../packages/mic-indicator-visibility-manager/default.nix)は [上流 moalhaddar/mic-indicator-visibilty-manager](https://github.com/moalhaddar/mic-indicator-visibilty-manager/tree/732eb61c452025b80a0a5c1943fbec86137a05d8) の revision `732eb61c452025b80a0a5c1943fbec86137a05d8` に固定する。
上流の設定スキーマと `prefs.js` を維持し、表示更新とストリーム判定の実装をローカル版に置き換える。`pactl` の実行パスは Nix store のパスに固定する。
上流の対応宣言は GNOME 46 だが、このパッケージは GNOME 50 のみを対応版として宣言する。
GNOME Shell の private API に依存するため、Shell 更新時には互換性の再確認が必要。取得・解析などの失敗時には標準のマイク使用表示へ戻す。
上流には LICENSE ファイルがなく、ライセンスを推定してパッケージメタデータに設定しない。
上流に同等の修正と GNOME 50 対応が入ったら、ローカル置換の除去と固定 revision の更新を再評価する。

2026-10-05 にパッケージのビルドと installCheck の11テストが通過した。AEC 単独とアプリ併用の判定、取得・解析失敗時の標準判定への復帰、問い合わせ中の状態変更、無効化・再有効化後の遅い応答を検査した。両ホストの Home Manager の拡張有効化・除外設定を評価し、既存の `checks.x86_64-linux.gnome-extensions` も通過した。GJS 1.88.1 / Gio と稼働中の PipeWire を使った読み取り専用の確認でも、パッケージ内の `pactl` による非同期 JSON 取得と AEC ストリームの除外が動作した。この確認では GNOME UI を模した入力オブジェクトを使い、実セッションの表示は変更していない。

実機での表示動作は未確認。[使い方の手動確認](../howtouse/audio-echo-cancel.md#gnome-のマイク使用表示)で、AEC のみ・アプリ使用中・アプリ終了後・拡張無効化時を確認する。

### 起動時の初期化競合の修正

初版の適用後、実機の拡張は `State: ERROR` となり、`quickSettings._volumeInput is undefined` で起動に失敗した。録音ストリームは AEC の内部2つのみだったが、除外処理が動かず標準表示が残っていた。
実機の GNOME Shell 50.4 の `libshell-18.so` に埋め込まれた `panel.js` では、Quick Settings の `_setupIndicators()` がネットワーク・Bluetooth モジュールの非同期 import 後に `_volumeInput` を生成する。`main.js` の拡張初期化はこの処理の完了を待たない。初版は `enable()` 時点で表示オブジェクトが存在すると仮定していたため、起動順序に依存した。初版のテストも生成済みの表示を用意しており、この競合を検査できていなかった。

修正版は [GNOME の InjectionManager](https://gjs.guide/extensions/topics/extension.html#injectionmanager) で、公開されている `InputIndicator` クラスの `_readInput()` に処理を取り付ける。このメソッドが本来の入力初期化を終えた後に、入力スライダーへ除外処理を取り付ける。既に表示が生成されている場合はその場で取り付け、同じ入力への二重取り付けを避ける。表示がまだない場合は正常に待機し、固定時間の待機やポーリングは使わない。無効化時にはクラスのメソッド・スライダーの処理を復元し、問い合わせもキャンセルする。

表示が後から生成されるケース、生成前に拡張を無効化するケース、入力初期化が繰り返されるケースの3回帰テストは初版で同じ TypeError を再現し、修正後は既存の11テストと合わせて14件が通過した。GJS 1.88.1 で、実機の埋込ソースから取得した `InputIndicator` のコンストラクターと `InjectionManager` を使い、遅延生成後の取り付けと無効化時のメソッド復元も確認した。UI 部品は代替し、`pactl` は稼働中の PipeWire を読み取った。検証では実セッションの画面を変更していない。修正版の適用後、利用者から動作しているように見えるとの報告があったが、表示の各条件を網羅した実画面の確認とは区別する。
