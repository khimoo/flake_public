# TwinDesk を使う

## PC と Android を接続する

各 PC の checkout で最新の変更を取得し、その PC の構成を適用する。

```sh
sudo nixos-rebuild switch --flake .#nixos-desktop
```

spin713 では構成名を `nixos-spin713` にする。ビルドは既存の設定でデスクトップへ回る。
初回は再起動して仮想カメラ用のカーネルモジュールを読み込む。

1. Niri の XDG Autostart（`xdg-desktop-autostart.target`）によるセッション開始時に `twindesk --hidden` でWaybar のトレイへ自動起動する（[twindesk.star](../../config/elements/twindesk.star)）。トレイアイコンまたはアプリ一覧から TwinDesk を開く（アプリ内の「Open at login」は二重登録になるためオフのままにする）。
2. Android に [v3.2.1 の Full APK](https://github.com/InukaAsith/TwinDesk/releases/download/v3.2.1/TwinDesk-3.2.1-full.apk) をインストールして開く（3.2 以降の新機能は PC と Android の両方を 3.2.1 以上にすると有効になる）。
3. 最初は同じ家庭内 Wi-Fi に接続する。Android の `Connect` → `Nearby` から PC を選ぶか、PC に表示した QR コードを読み取り、ペアリングする。
4. 通知、SMS、画面操作など、使う機能の権限を Android 側で許可する。
5. 文字のコピーと小さなファイルの送信を試す。

1 対 1 モードでは Android は一度に 1 台の PC と接続する（接続先の変更は Android の `Connect` にある `Switch` を使う）。複数台の PC と Android を同時に繋ぐ場合は、各端末の設定で **Multi-device** を有効にする（Multi-device モードでは Camera タブは使えない）。
USB 接続や Android アプリの個別表示には、Android の開発者向けオプションと USB／ワイヤレスデバッグの設定が必要。
大学 Wi-Fi で端末間通信が禁止されている場合は、USB または Bluetooth／Wi-Fi Direct の接続を試す。

## 更新と無効化

バージョンは [flake.nix](../../flake.nix) の `twindesk.url` で選び、`nix flake update twindesk` と再適用で更新する。
無効化する場合は、desktop と spin713 のハードウェアプロファイルが `requires` に挙げる [personal_pc.star](../../config/elements/personal_pc.star) の `requires` から `twindesk` を外して再適用する。

## Nix パッケージと udev の補完

[公式 v3.2.1 の flake](https://github.com/InukaAsith/TwinDesk/blob/v3.2.1/flake.nix) は
`shared/` 全体（`shared/web`・`shared/airplay` を含む）をコピーするようになったが、
TwinDesk Web で参照する `web/` と `android/app/src/main/assets/web` はまだ含めない。
[パッケージ定義](../../packages/twindesk/default.nix) は不足する Web 用の画面を追加し、
installCheck で `shared/web/webwire.js` と合わせて確認する。
また、上流モジュールの `services.udev.extraRules`（`GROUP="input"`）は `hardware.uinput.enable` の `GROUP="uinput"` に上書きされるため、[twindesk.star](../../config/elements/twindesk.star) で `GROUP:="input"` を補う。
上流がこれらを解消した版へ更新するときは、補完を外せるか確認する。

[公式の NixOS 手順](https://github.com/InukaAsith/TwinDesk/blob/v3.2.1/docs/nixos.md)
