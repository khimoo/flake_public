# memex の Google Drive 同期

vault の中で git に載せない資料を、`rclone bisync` で Google Drive の `gdrive:memex-files` と双方向に同期します。同期する資料は vault 直下の `.drive-sync-filter` で選びます。ファイルの実体は各 PC に置き、vault の `.gitignore` で git から外します。

機能フラグ `memexSync` で有効になります。`nixos-desktop` と `nixos-spin713` では有効です。スタンドアロンの home-manager 環境では、ユーザーごとの home モジュールで `local.profile.features` と `local.profile.memexRoot` を設定してください。現在の vault プロファイルは Linux 環境にのみ対応しています。

設計ドキュメント: [memex の Google Drive 同期の設計](../architecture/memex-drive-sync.md)

## 同期する資料を選ぶ

`.drive-sync-filter` は [rclone のフィルタ構文](https://rclone.org/filtering/) で書きます。最後の行は `- **` にします。

```text
+ /Assets/attachments/**
+ /Knowledge/Reading/**.pdf
- **
```

同じ資料を `.gitignore` にも書き、git に入らないようにします。
フィルタを変えると、両 PC で通常の同期が止まり、resync を求められます（下の「フィルタを変えたとき」）。資料を足すたびにフィルタを変えなくて済むよう、ファイル名ではなくパターンで書きます。

## 新しいマシンでの初期設定手順

1. `switch` を実行します（vault がクローンされ、同期用の systemd unit が登録されます）。
2. `memex-setup` を実行します。リモート `gdrive` に接続できなければ `rclone config` を起動します。
3. Drive 側と手元の資料を確認し、必要なら同期の外へバックアップしてから、初回の同期を実行します。

```sh
memex-sync --resync --dry-run
memex-sync --resync
memex-sync
```

`rclone config` では、リモート名を `gdrive`、`Storage` を `drive` にします。
Google Drive の認証情報は各マシンの `~/.config/rclone/rclone.conf` に保存され、このリポジトリや memex-nix には含まれません。
初回の同期が済むまで、定期実行の `memex-sync.service` は「同期の記録がありません」で失敗し、通知が出ます。

### rclone の共有 OAuth クライアントから移行する場合

rclone の共有 OAuth クライアントは 2026 年中に廃止予定のため、個人の client_id と client_secret を取得して使用してください（詳細は [rclone 公式手順](https://rclone.org/drive/#making-your-own-client-id) を参照）。
共有クライアントで作成した既存ファイルは、新しいクライアントで `scope` を `drive.file` に設定した場合、見えなくなることがあります。そのため、移行後の新しいクライアントでは `scope` を `drive`（Drive 全体の読み書き・削除権限）に指定して認可を行ってください。
リモート名、同期先、同期履歴に変更がない場合、認証情報の変更だけで resync する必要はありません。
OAuth 同意画面の設定が「Testing」のままだと認可の有効期限が 7 日間で切れてしまうため、継続利用する場合は公開ステータス（In production）になっているか確認してください。

## 日常的な運用

`Assets/attachments/` への貼り付けはすぐに、それ以外の資料は 15 分ごとの定期実行で同期されます。他のマシンで追加されたファイルは、次の同期で取り込まれます。

```sh
memex-sync              # 今すぐ同期
memex-sync --dry-run    # 変更内容だけを表示
journalctl --user -u memex-sync -f
```

ファイルの削除も双方向に反映されます。消えたり上書きされたりした版は、`${XDG_DATA_HOME:-$HOME/.local/share}/memex/files-backups/<host>/<runid>` と `gdrive:memex-files-backups/<host>/<runid>` へ退避されます。退避データは、保持期限を決めるまで削除しないでください。

## フィルタを変えたとき

フィルタを変えて両 PC に git で届けたあと、それぞれの PC で差分を確認してから resync します。

```sh
MEMEX_FORCE_RESYNC=1 memex-sync --resync --dry-run
MEMEX_FORCE_RESYNC=1 memex-sync --resync
```

resync は両側の和集合を作ります。消したはずのファイルが戻ることがあるので、dry-run の出力を確認してください。

## トラブルシューティング

エラーが発生した場合は対処方法が画面に表示されるため、まずはその指示に従ってください。

- `remote 'gdrive' が未定義です`: `rclone config` でリモート設定を作成してください（`memex-setup` の案内に従う）。
- `認証に失敗しました`: 認証トークンの期限が切れています。`rclone config reconnect gdrive:` を実行して再認証してください。
- `同期の記録がありません`: その PC で初回の同期がまだです。上の初期設定手順の 3 を実行してください。
- `filters file has changed`: フィルタが変わりました。上の「フィルタを変えたとき」を実行してください。
- `.conflict` や番号付きのファイルが生成された: 2 台の端末で同時に同じファイルが更新されました。内容を確認し、採用する方を元のファイル名に戻すか、ノートのリンクを直してください。
- 復元したい: 両 PC の自動同期を止め、退避データから同期先へ戻して内容を照合してから再開してください。

memex-nix の変更を試すときは、`--override-input memex-nix path:/path/to/memex-nix` で評価し、`flake.lock` の更新とは分けてください。
