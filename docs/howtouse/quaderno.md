# Quaderno の取り込みと送信

Fujitsu Quaderno A4 Gen2 と、同じ LAN 内で PDF を受け渡します。
1 分ごとに Quaderno を探し、見つかったら、利用者に入った要素に応じて次の順に処理します。

1. `use_quaderno_archive`: Quaderno で作成・書き込みした PDF を、自分用サーバのアーカイブへ ssh で送って取り込む
2. `quaderno_send`: 送信用フォルダ（Send）に置いた PDF を Quaderno の `Document/Received` へ送る

Quaderno はスリープ中は Wi-Fi から外れるので、受け渡しは Quaderno のスリープを解除してから 1 分ほどで始まります。
ホストに `quaderno_bluetooth` を書いた機体は、同じ LAN に Quaderno が見つからないとき、Bluetooth でつないで受け渡します（[Bluetooth で受け渡す](#bluetooth-で受け渡す)）。
[nixos-desktop.toml](../../config/hosts/nixos-desktop.toml) と [nixos-spin713.toml](../../config/hosts/nixos-spin713.toml) の pomu は `[[users]]` の `purposes` で `read_materials` を選び、`requires` の `quaderno_send` と、Quaderno を探す `quaderno` が入ります。取り込みのクライアント `use_quaderno_archive` も `read_materials` の `requires` から入り、`requires` の `find_home_server` が `needs` に `tailscale` を挙げるので、tailnet に入らない機体で `read_materials` を選ぶと confgen が止まります。取り込んだ PDF と取り込みの記録は、自分用サーバ（`run_home_server` を選んだ利用者のいる nixos-desktop）が持ちます。サーバの側は、nixos-desktop の pomu の `purposes` にある `run_home_server` から入る `serve_quaderno_archive` で、取り込み先を `quaderno_archive` で指定しています。記録がサーバの1か所にあるので、desktop と spin713 のどちらが Quaderno を見つけても、同じ改訂を二度取り込みません。自分用サーバに接続できないとき（出先でデスクトップの電源が切れているときなど）は取り込みを飛ばし、PDF は Quaderno に残ります。取り込みと送信を無効にするには、利用者の `purposes` から `read_materials` を外します。サーバを止めるには、nixos-desktop の pomu の `purposes` から `run_home_server` を外します。

設計ドキュメント: [Quaderno の取り込みと送信の設計](../architecture/quaderno.md)

## 初回ペアリング手順

1. Quaderno の Wi-Fi を有効にし、設定画面に表示される IP アドレスを確認する
2. `curl -s http://<IP>:8080/register/information` を実行し、`model_name` などの JSON が返ってくることを確認する
3. `dptrp1 --addr <IP> register` を実行し、Quaderno の画面に表示された PIN を端末に入力する

ペアリングが成功すると `~/.config/dpt/deviceid.dat` と `~/.config/dpt/privatekey.dat` が生成され、以降の認証にはこの 2 つのファイルが使用されます。
これらはデバイス個別の認証鍵であるため、Git リポジトリには含めないでください。
ペアリングは、`quaderno` が入る利用者のマシンごとに必要です。

## PDF を送る

`~/Quaderno/Send` に PDF を置き、Quaderno のスリープを解除します。1 分ほどで `Document/Received` に届き、Send からは消えます。
同じ名前の文書が Received にあれば上書きせず、`a (a).pdf`、`a (b).pdf` のように英字を付けて送ります。古い版は Quaderno 側で消してください。
送り先と Send の場所は、ホストの `quaderno_send_remote` と `quaderno_send_dir` で変えられます。

## Bluetooth で受け渡す

公共の Wi-Fi のように、PC と Quaderno を同じ LAN に置けない場所で使います。
PC が Quaderno の Bluetooth のネットワーク（PAN）に接続し、その上で Wi-Fi のときと同じ受け渡しをします。
[nixos-spin713.toml](../../config/hosts/nixos-spin713.toml) は `quaderno_bluetooth` を書いています。

機体ごとに、次の準備を一度だけ行います。

1. Quaderno の設定で Bluetooth を有効にし、Bluetooth Low Energy (BLE) は「無効にする」のままにする。BLE を有効にすると、PC から Bluetooth で接続できなくなる
2. PC と Quaderno を Bluetooth でペアリングする（GNOME の設定の Bluetooth、または `bluetoothctl` の `pair` と `trust`）
3. ホストの `quaderno_bluetooth` に Quaderno の Bluetooth アドレスを書き、構成を適用する。アドレスは `bluetoothctl devices` の `FMVDP41_…` の行にある
4. [初回ペアリング手順](#初回ペアリング手順) が済んでいない機体は、`nmcli connection up id quaderno-pan` でつないでから `dptrp1 --addr 172.25.48.1 register` を実行する

準備が済めば、使い方は Wi-Fi のときと同じです。Quaderno のスリープを解除すると、1 分ほどで受け渡しが始まります。
同じ LAN に Quaderno が居るときは、Bluetooth を使いません。

つながらないときは、手で接続して確かめます。

```sh
nmcli connection up id quaderno-pan
curl -s http://172.25.48.1:8080/register/information
nmcli connection down id quaderno-pan
```

Quaderno がスリープしていると、`nmcli connection up` は 5 秒ほどで「Bluetooth 接続が失敗またはタイムアウトしました」と表示して終わります。

## 日常の運用

自動で処理されるため手動での操作は不要です。今すぐ受け渡しを行いたい場合は `quaderno-transfer` を実行してください。

取り込み先は `/mnt/backup/quaderno`（`quaderno_archive`）であり、デバイス内のフォルダ構造がそのまま再現されます（`<quaderno_archive>/Document/...`）。
Google Drive への自動アップロードは行われません。クラウドへ保存したい場合は手動でアップロードしてください。

ローカル側はアーカイブとして扱うため、デバイス側で削除された文書も手元にはそのまま残ります。
また、デバイス側でファイル名の変更や移動を行っても、手元には変更前の名前と配置のまま保持されます。これは取り込み判定に `entry_id` と `file_revision` の対応のみを使用しているためです。手元の配置も一致させたい場合は手動で整理してください。
注釈や手書きを追記した文書は上書き保存され、追記前の過去バージョンは保持されません。

各文書のどのリビジョンまで取り込み済みかは `~/.local/state/quaderno/state.json` で管理されています。このファイルを削除すると、次回の実行時に全ファイルを再取り込みします。

## 動作確認

```sh
systemctl --user status quaderno-transfer
journalctl --user -u quaderno-transfer
```

Quaderno がスリープ状態の場合はデバイスを発見できず、「見つかりません」と表示して正常終了します。これは正常な挙動です。
認証エラーや、取り込み・送信自体に失敗した場合は、非ゼロのステータスコードで終了します。

同一 LAN 内に他の Digital Paper 機器が存在し、意図しない機器へ接続されてしまう場合は、ホストの `quaderno_serial` にシリアル番号を指定することで特定デバイスのみに接続を限定できます。
