# Quaderno の取り込みと送受信

Fujitsu Quaderno A4 Gen2 と PC 間で PDF を送受信・アーカイブするための機能です。主な役割は以下の3点です。

1. **送信**: `~/Quaderno/Send` に配置した PDF を、Quaderno の受け渡しフォルダ `Document/PC-Exchange` へ送信します。1 分ごとに監視し、未送信ファイルがあればスリープ解除中の Quaderno を検出して転送します。`quaderno-send` コマンドによる即時送信も可能です。
2. **受信**: `quaderno-receive` コマンドを実行し、`Document/PC-Exchange` 内の PDF を手元の `~/Quaderno/Received` へ取得します。
3. **アーカイブ取り込み**: Quaderno で作成・編集した PDF を、SSH 経由で自分用サーバーのアーカイブへバックアップします。1 時間ごとの定期実行に加え、`quaderno-send` や `quaderno-receive` の実行時にも行われます。

送受信は `quaderno_exchange`、アーカイブ取り込みは `use_quaderno_archive` が担当します。

### 動作概要と設定

* **スリープと探索**: Quaderno はスリープ中は通信できません。送受信処理は Quaderno のスリープを解除している間に行われます。同一 LAN 内に見つからない場合は、ペアリング済みの Bluetooth（PAN）経由で接続を試みます（詳細: [Bluetooth で受け渡す](#bluetooth-で受け渡す)）。
* **利用設定**: [nixos-desktop.toml](../../config/hosts/nixos-desktop.toml) や [nixos-spin713.toml](../../config/hosts/nixos-spin713.toml) の `[[users]]` にある `purposes` に `read_materials` を指定すると、必要な機能（`quaderno_exchange`、`quaderno`、`use_quaderno_archive`）が有効化されます。
  * `use_quaderno_archive` は `find_home_server` を必要とし、これはさらに `tailscale` を要求します。Tailscale ネットワーク（Tailnet）に参加していない環境で `read_materials` を指定すると、`confgen` の処理が停止するため注意してください。
* **サーバー側の挙動**: 取り込んだ PDF と履歴データは、`run_home_server`（`serve_quaderno_archive`）が有効な自分用サーバー（`nixos-desktop`）で一元管理されます。取り込み先パスは `quaderno_archive` で指定します。
  * 履歴が一括管理されているため、`desktop` と `spin713` のどちらから Quaderno を検知しても、同一のリビジョンを二重に取り込むことはありません。
  * 外出先などでサーバーに接続できない場合は取り込みをスキップし、PDF は Quaderno 内に保持されます。
* **無効化方法**:
  * クライアント機能の停止: 利用者の `purposes` から `read_materials` を削除
  * サーバー機能の停止: `nixos-desktop` の `purposes` から `run_home_server` を削除

設計ドキュメント: [Quaderno の取り込みと送信の設計](../architecture/quaderno.md)

---

## 初回ペアリング手順

1. Quaderno の Wi-Fi を有効にし、本体の設定画面で IP アドレスを確認します。
2. 端末で以下のコマンドを実行し、`model_name` を含む JSON が返ってくることを確認します。
   ```sh
   curl -s http://<IP>:8080/register/information
   ```
3. 以下のコマンドを実行し、Quaderno の画面に表示された PIN を入力します。
   ```sh
   dptrp1 --addr <IP> register
   ```

ペアリングが完了すると `~/.config/dpt/deviceid.dat` と `~/.config/dpt/privatekey.dat` が生成され、以降の認証に使用されます。これらはデバイス固有の秘密鍵であるため、**Git リポジトリには絶対にコミットしないでください**。なお、ペアリングは `quaderno` を利用するマシンごとに実施する必要があります。

---

## PDF を送る

```sh
quaderno-send report.pdf
```

PDF を `~/Quaderno/Send` にコピーし、即座に Quaderno へ送信します。送信が完了した PDF は Quaderno の `Document/PC-Exchange` に格納され、手元の `Send` フォルダからは削除されます。Quaderno がスリープ中の場合、ファイルは `Send` に残り、スリープを解除すると 1 分以内に自動転送されます。

* **Send フォルダへの直接配置**: ファイルマネージャー等で `~/Quaderno/Send` に直接 PDF を配置した場合も同様に送信されます。引数なしで `quaderno-send` を実行すると、`Send` 内の未送信ファイルを即座に転送します。
* **送信待ちの確認とキャンセル**: `ls ~/Quaderno/Send` で未送信ファイルを確認できます。送信前にファイルを削除すれば転送をキャンセルできます。
* **同名ファイルの扱い**: 送信先に同名ファイルが既に存在する場合、上書きは行われず `report (a).pdf`、`report (b).pdf` のように枝番を付与して保存されます。不要な古い版は Quaderno 側で手動削除してください。
* **パスのカスタマイズ**: Quaderno 上の受け渡しフォルダとローカルの送信フォルダは、ホスト設定の `quaderno_exchange_remote` および `quaderno_send_dir` で変更可能です。受け渡しフォルダが Quaderno 上に存在しない場合は自動生成されます。

---

## PDF を手元で受け取る

```sh
quaderno-receive
```

Quaderno の `Document/PC-Exchange` にある PDF を、手元の `~/Quaderno/Received` へ取得します。自分用サーバーを経由しないため、外出先のノート PC 単体でも利用可能です。
受信処理はコマンド実行時のみ行われます。Quaderno がスリープ中の場合は、スリープを解除してから再実行してください。
`PC-Exchange` 以外のフォルダにある文書を取り出したい場合は、あらかじめ Quaderno 端末上でファイルを `PC-Exchange` フォルダへ移動させてから実行します。

* **取得対象**: まだ手元にない文書、および Quaderno 側で手書きメモ等の追記・編集が行われた文書です。
* **上書きの挙動**: Quaderno 側で更新された文書を受信すると、手元の `Received` 内のファイルは最新版で上書きされます。手元で編集・加工する場合は別のディレクトリへ退避してください。
* **保存場所と自動クリーンアップ**: `~/Quaderno/Received` は `~/.cache/quaderno/Received` へのシンボリックリンクです。7 日間アクセスがなかったファイルはキャッシュとして自動削除されます。永続的なバックアップはサーバー側のアーカイブに保存されます。
* **削除時の同期**: Quaderno 側で削除された文書は手元に残ります。また、手元でファイルを削除した場合でも、Quaderno 側で再度更新されない限り再取得は行われません。全件を再取得したい場合は、受信履歴ファイル `~/.cache/quaderno/received.json` を削除してください。

---

## Bluetooth で受け渡す

公共 Wi-Fi など、PC と Quaderno を同一 LAN に接続できない環境で使用します。
PC から Quaderno の Bluetooth ネットワーク（PAN）へ接続し、Wi-Fi 接続時と同様の送受信を行います。ホスト側の設定変更は不要で、ペアリング済みの機器であれば自動的に Bluetooth 接続を試行します。

### 事前準備（マシンごとに初回のみ実施）

1. **Quaderno の設定**: 本体で Bluetooth を有効にします。※「Bluetooth Low Energy (BLE)」の設定は必ず**「無効にする」**のままにしてください（有効にすると PC から接続できなくなります）。
2. **ペアリング**: PC と Quaderno を Bluetooth でペアリングします（GNOME の設定画面、または `bluetoothctl` の `pair` / `trust` コマンドを使用）。
3. **登録（未実施の場合）**: [初回ペアリング手順](#初回ペアリング手順)を完了していないマシンでは、GNOME の設定から Quaderno のネットワークへ接続した状態で以下のコマンドを実行します。
   ```sh
   dptrp1 --addr 172.25.48.1 register
   ```

※接続対象は、ペアリング済みデバイスのうち名称が `FMVDP` または `DPT-` で始まる機器です（`bluetoothctl devices Paired` で確認可能）。

### 動作仕様と注意点

* 準備完了後の操作方法は Wi-Fi 接続時と同様です。
* **同一 LAN 内に Quaderno が見つかる場合は、Bluetooth ではなく Wi-Fi 接続が優先されます。**
* 接続できない場合は、GNOME の設定画面から手動で Quaderno のネットワークへ接続し、以下のコマンドで応答を確認してください。
  ```sh
  curl -s http://172.25.48.1:8080/register/information
  ```
  ※Quaderno がスリープ中の場合、接続試行は約 5 秒でタイムアウトします。
* 転送処理中のみ、NetworkManager 上に一時的な接続プロファイル `quaderno-pan` が作成され、処理完了後に自動破棄されます。

---

## 日常の運用

アーカイブへの取り込みはバックグラウンドで自動実行されるため、通常は手動操作の必要はありません。即座に取り込みを行いたい場合は `quaderno-transfer` を実行してください。取り込みの間隔は、ホスト設定の `quaderno_archive_interval`（秒単位）で変更できます。

* **アーカイブの構造**: 取り込み先は `/mnt/backup/quaderno`（`quaderno_archive`）配下となり、端末内のフォルダ構造がそのまま再現されます（例: `<quaderno_archive>/Document/...`）。
* **外部クラウド非連携**: Google Drive 等のパブリッククラウドへの自動アップロード機能はありません。クラウドへの保存が必要な場合は手動で同期してください。
* **削除・変更時の挙動**:
  * 手元側はバックアップアーカイブとして機能するため、Quaderno 端末側で文書を削除してもアーカイブ側のファイルは保持されます。
  * 端末側でファイル名の変更やフォルダ移動を行っても、アーカイブ側の配置は更新されません（取り込み判定に `entry_id` と `file_revision` のみを用いているため）。配置を一致させたい場合は手動で整理してください。
  * 手書きメモや注釈を追記した文書は上書き保存され、追記前の旧バージョンは保持されません。
* **履歴管理**: 各ファイルの取り込み済みリビジョンは `~/.local/state/quaderno/state.json` で追跡されています。このファイルを削除すると、次回実行時にすべてのファイルが再取り込みされます。

---

## 動作確認

以下のコマンドで各サービスの状態や実行ログを確認できます。

```sh
systemctl --user status quaderno-transfer quaderno-send
journalctl --user -u quaderno-transfer -u quaderno-send
```

`quaderno-transfer` は 1 時間ごとの定期取り込み、`quaderno-send` は 1 分ごとの定期送信を担います。なお、`quaderno-send` は `Send` フォルダが空の間は実行されません。

* **スリープ時のログ**: Quaderno がスリープ状態の場合は探索に失敗し、「見つかりません」とログ出力して正常終了します（これは想定通りの仕様です）。
* **エラーハンドリング**: 認証エラーや通信障害、送受信処理自体の失敗時は、非ゼロのステータスコードで異常終了します。
* **デバイスの特定**: 同一 LAN 内に他の Digital Paper 互換機器が存在し意図しない機器へ接続される場合は、ホスト設定の `quaderno_serial` にシリアル番号を指定することで接続対象を固定できます。
