# Quaderno の取り込みと送信

Fujitsu Quaderno A4 Gen2 と同じ LAN 内で、PDF ファイルの受け渡しを行います。
1 分ごとに Quaderno を探索し、見つかった場合は利用者の設定（要素）に応じて以下の順で処理を実行します。

1. **`use_quaderno_archive`**: Quaderno で作成・編集した PDF を、自分用サーバのアーカイブへ SSH 経由で取り込む
2. **`quaderno_send`**: 送信用フォルダ（`Send`）に置いた PDF を、Quaderno の `Document/Received` へ送信する

### 動作概要と設定

* **スリープと探索**: Quaderno はスリープ中に Wi-Fi が切断されるため、スリープを解除してから 1 分ほどで同期が開始します。同一 LAN 内に見つからない場合は、ペアリング済みの Bluetooth（PAN）経由で接続を試みます（詳細: [Bluetooth で受け渡す](#bluetooth-で受け渡す)）。
* **利用設定**: [nixos-desktop.toml](../../config/hosts/nixos-desktop.toml) や [nixos-spin713.toml](../../config/hosts/nixos-spin713.toml) の `[[users]]` にある `purposes` で `read_materials` を指定すると、必要な機能（`quaderno_send`、`quaderno`、`use_quaderno_archive`）が読み込まれます。
  * `use_quaderno_archive` は `find_home_server` を必要とし、それがさらに `tailscale` を要求します。Tailnet に入らない環境で `read_materials` を選択すると `confgen` が停止するため注意してください。
* **サーバ側の挙動**: 取り込んだ PDF と履歴データは、`run_home_server`（`serve_quaderno_archive`）が有効な自分用サーバ（`nixos-desktop`）が一元管理します。取り込み先は `quaderno_archive` で指定します。
  * 記録が一括管理されているため、`desktop` と `spin713` のどちらが Quaderno を検知しても、同じ改訂版を二重に取り込むことはありません。
  * 出先などで自分用サーバに接続できない場合は取り込み処理をスキップし、PDF は Quaderno 内に保持されます。
* **無効化方法**:
  * 機能の無効化：利用者の `purposes` から `read_materials` を削除
  * サーバの停止：`nixos-desktop` の `purposes` から `run_home_server` を削除

設計ドキュメント: [Quaderno の取り込みと送信の設計](../architecture/quaderno.md)

---

## 初回ペアリング手順

1. Quaderno の Wi-Fi を有効にし、設定画面で IP アドレスを確認します。
2. 端末で `curl -s http://<IP>:8080/register/information` を実行し、`model_name` などの JSON が返ることを確認します。
3. `dptrp1 --addr <IP> register` を実行し、Quaderno の画面に表示された PIN を入力します。

ペアリングが成功すると `~/.config/dpt/deviceid.dat` と `~/.config/dpt/privatekey.dat` が生成され、以降の認証に使用されます。
これらはデバイス固有の認証鍵であるため、**Git リポジトリには含めないでください**。
ペアリングは `quaderno` を利用するマシンごとに必要です。

---

## PDF を送る

`~/Quaderno/Send` に PDF を配置し、Quaderno のスリープを解除します。1 分ほどで Quaderno の `Document/Received` に届き、`Send` フォルダからは自動的に削除されます。

* **同名ファイルの扱い**: 送信先に同名文書が存在する場合、上書きせず `a (a).pdf` や `a (b).pdf` のように英字を付与して送信します。古い版は Quaderno 側で手動削除してください。
* **設定変更**: 送信先および `Send` フォルダの場所は、ホストの `quaderno_send_remote` と `quaderno_send_dir` で変更できます。

---

## Bluetooth で受け渡す

公共 Wi-Fi など、PC と Quaderno を同じ LAN に配置できない環境で使用します。
PC から Quaderno の Bluetooth ネットワーク（PAN）へ接続し、Wi-Fi 時と同様の受け渡しを行います。ホスト側の設定は不要で、ペアリング済みの機器が自動的に Bluetooth を使用します。

### 事前準備（マシンごとに初回のみ実施）

1. **Quaderno の設定**: Bluetooth を有効にします。※「Bluetooth Low Energy (BLE)」は**「無効にする」**のままにしてください（有効にすると PC から接続できなくなります）。
2. **ペアリング**: PC と Quaderno を Bluetooth ペアリングします（GNOME の設定画面、または `bluetoothctl` の `pair` / `trust` コマンド）。
3. **登録（未実施の場合）**: [初回ペアリング手順](#初回ペアリング手順)が未完了のマシンは、GNOME の設定で Quaderno のネットワークに接続した状態で `dptrp1 --addr 172.25.48.1 register` を実行します。

接続先は、ペアリング済み機器のうち名前が `FMVDP` または `DPT-` で始まるものです（`bluetoothctl devices Paired` で確認可能）。

### 使い方・挙動

* 準備完了後は Wi-Fi 時と同様、Quaderno のスリープを解除すると 1 分ほどで受け渡しが始まります。
* **同じ LAN 内に Quaderno が存在する場合は、Bluetooth を使用せず Wi-Fi を優先します。**
* 接続できない場合は、GNOME 設定から手動で Quaderno のネットワークに接続し、以下のコマンドで応答を確認してください。
  ```sh
  curl -s http://172.25.48.1:8080/register/information
  ```
  ※Quaderno がスリープ中の場合、接続は約 5 秒でタイムアウトします。
* 転送中のみ、NetworkManager 上に `quaderno-pan` という接続が作成され、完了後に自動消去されます。

---

## 日常の運用

処理は自動実行されるため、通常手動での操作は不要です。今すぐ受け渡しを行いたい場合は `quaderno-transfer` を実行してください。

* **取り込み構造**: 取り込み先は `/mnt/backup/quaderno`（`quaderno_archive`）であり、デバイス内のフォルダ構造がそのまま再現されます（`<quaderno_archive>/Document/...`）。
* **クラウド非連携**: Google Drive 等への自動アップロードは行われません。クラウド保存が必要な場合は手動でアップロードしてください。
* **削除・変更の同期**:
  * 手元側はアーカイブとして扱うため、デバイス側で削除された文書も残ります。
  * デバイス側でファイル名の変更や移動を行っても、手元側の配置は更新されません（取り込み判定に `entry_id` と `file_revision` のみを使用しているため）。配置を一致させたい場合は手動で整理してください。
  * 注釈や手書きを追記した文書は上書き保存され、追記前の過去バージョンは保持されません。
* **履歴管理**: 各文書の取り込み済みリビジョンは `~/.local/state/quaderno/state.json` で管理されています。このファイルを削除すると、次回実行時に全ファイルを再取り込みします。

---

## 動作確認

以下のコマンドでサービスの状態とログを確認できます。

```sh
systemctl --user status quaderno-transfer
journalctl --user -u quaderno-transfer
```

* **スリープ時**: Quaderno がスリープ状態の場合はデバイスを発見できず、「見つかりません」と表示して正常終了します（仕様通りの動作です）。
* **エラー時**: 認証エラーや取り込み・送信自体に失敗した場合は、非ゼロのステータスコードで終了します。
* **デバイスの固定**: 同一 LAN 内に他の Digital Paper 機器が存在し誤接続される場合は、ホストの `quaderno_serial` にシリアル番号を指定することで特定デバイスのみに接続を限定できます。
