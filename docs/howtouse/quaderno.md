# Quaderno の取り込み

Fujitsu Quaderno A4 Gen2 で作成した手書き PDF を、同じ LAN 内に接続している際に 1 時間ごとに自動でローカルへ取り込みます。
データの同期はデバイスから手元への一方向のみであり、デバイス側のファイルを書き換えることはありません。
設定は [home-manager-pomu.nix](../../hosts/nixos-desktop/home-manager-pomu.nix) の `local.quaderno` に記載されており、nixos-desktop のみで有効化しています。複数台で有効にすると、両方のマシンが全件を取り込む動作になります。

設計ドキュメント: [Quaderno の取り込みの設計](../architecture/quaderno.md)

## 初回ペアリング手順

1. Quaderno の Wi-Fi を有効にし、設定画面に表示される IP アドレスを確認する
2. `curl -s http://<IP>:8080/register/information` を実行し、`model_name` などの JSON が返ってくることを確認する
3. `dptrp1 --addr <IP> register` を実行し、Quaderno の画面に表示された PIN を端末に入力する

ペアリングが成功すると `~/.config/dpt/deviceid.dat` と `~/.config/dpt/privatekey.dat` が生成され、以降の認証にはこの 2 つのファイルが使用されます。
これらはデバイス個別の認証鍵であるため、Git リポジトリには含めないでください。

## 日常の運用

自動で処理されるため手動での操作は不要です。今すぐ取り込みを行いたい場合は `quaderno-pull` を実行してください。

取り込み先は `/mnt/backup/quaderno`（`archiveDir`）であり、デバイス内のフォルダ構造がそのまま再現されます（`<archiveDir>/Document/...`）。
Google Drive への自動アップロードは行われません。クラウドへ保存したい場合は手動でアップロードしてください。

ローカル側はアーカイブとして扱うため、デバイス側で削除された文書も手元にはそのまま残ります。
また、デバイス側でファイル名の変更や移動を行っても、手元には変更前の名前と配置のまま保持されます。これは取り込み判定に `entry_id` と `file_revision` の対応のみを使用しているためです。手元の配置も一致させたい場合は手動で整理してください。
注釈や手書きを追記した文書は上書き保存され、追記前の過去バージョンは保持されません。

各文書のどのリビジョンまで取り込み済みかは `~/.local/state/quaderno/state.json` で管理されています。このファイルを削除すると、次回の実行時に全ファイルを再取り込みします。

## 動作確認

```sh
systemctl --user status quaderno-pull
journalctl --user -u quaderno-pull
```

Quaderno がスリープ状態の場合はデバイスを発見できず、「見つかりません」と表示して正常終了します。これは正常な挙動です。
認証エラーやダウンロード処理自体に失敗した場合は、非ゼロのステータスコードで終了します。

同一 LAN 内に他の Digital Paper 機器が存在し、意図しない機器へ接続されてしまう場合は、`local.quaderno.serial` にシリアル番号を指定することで特定デバイスのみに接続を限定できます。
