# TwinDesk を使う

## PC と Android を接続する

各 PC の checkout で最新の変更を取得し、その PC の構成を適用する。

```sh
sudo nixos-rebuild switch --flake .#nixos-desktop
```

spin713 では構成名を `nixos-spin713` にする。ビルドは既存の設定でデスクトップへ回る。
初回は再起動して仮想カメラ用のカーネルモジュールを読み込む。

1. PC のアプリ一覧から TwinDesk を開く。
2. Android に [v3.0.0 の Full APK](https://github.com/InukaAsith/TwinDesk/releases/download/v3.0.0/TwinDesk-3.0.0-full.apk) をインストールして開く。
3. 最初は同じ家庭内 Wi-Fi に接続する。Android の `Connect` → `Nearby` から PC を選ぶか、PC に表示した QR コードを読み取り、ペアリングする。
4. 通知、SMS、画面操作など、使う機能の権限を Android 側で許可する。
5. 文字のコピーと小さなファイルの送信を試す。

Android は一度に 1 台の PC と接続する。接続先の変更は Android の `Connect` にある `Switch` を使う。
USB 接続や Android アプリの個別表示には、Android の開発者向けオプションと USB／ワイヤレスデバッグの設定が必要。
大学 Wi-Fi で端末間通信が禁止されている場合は、USB または Bluetooth／Wi-Fi Direct の接続を試す。

## 更新と無効化

バージョンは [flake.nix](../../flake.nix) の `twindesk.url` で選び、`nix flake update twindesk` と再適用で更新する。
無効化する場合は [machine_nixos_desktop.star](../../config/elements/machine_nixos_desktop.star) と [machine_nixos_spin713.star](../../config/elements/machine_nixos_spin713.star) の `requires` から `twindesk` を外して再適用する。

## Nix パッケージの補完

[公式 v3.0.0 の flake](https://github.com/InukaAsith/TwinDesk/blob/v3.0.0/flake.nix) は
`shared/` の直下のファイルと一部のディレクトリだけをコピーするため、起動時に必要な
`shared/web/webwire.js` が欠ける。[パッケージ定義](../../packages/twindesk/default.nix) は
不足する共有ディレクトリと Web 用の画面を追加し、installCheck で確認する。
上流がこれらを同梱する版へ更新するときは、この補完を外せるか確認する。

[公式の NixOS 手順](https://github.com/InukaAsith/TwinDesk/blob/v3.0.0/docs/nixos.md)
