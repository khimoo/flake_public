# memex の Google Drive 同期

vault 配下の `Assets/attachments/`（添付ファイル）、`Assets/references/`（papis ライブラリ）、`Assets/Originals/`（原本データ）を、`rclone bisync` を用いて Google Drive と双方向で同期します。ファイルの実体はローカル端末上にも保持し、Git リポジトリ管理からは除外しています（vault の `.gitignore` で設定済み）。

- `Assets/attachments/` ↔ `gdrive:memex-attachments`（機能フラグ `memexSync`）
- `Assets/references/` ↔ `gdrive:papis-library`（機能フラグ `referenceSync`、使用方法は [papis-gdrive-sync.md](./papis-gdrive-sync.md) を参照）
- `Assets/Originals/` ↔ `gdrive:memex-originals`（`memexSync` 有効時）

`nixos-desktop` および `nixos-spin713` では両機能が有効化されています。スタンドアロンの home-manager 環境では、ユーザーごとの home モジュールで `local.profile.features` と `local.profile.memexRoot` を設定してください。なお、現在の vault プロファイルは Linux 環境にのみ対応しています。

設計ドキュメント: [memex の Google Drive 同期の設計](../architecture/memex-attachments-sync.md)

## 新しいマシンでの初期設定手順

1. `switch` を実行します（vault がクローンされ、同期用の systemd unit が登録されます）。
2. `memex-setup` を実行します。

`memex-setup` は、リモート設定 `gdrive` に接続できない場合に自動で `rclone config` を立ち上げ、その後に初回同期を実行します。途中で処理を中断しても、再実行すれば完了している工程はスキップされます。
`rclone config` の設定では、リモート名を `gdrive`、`Storage` を `drive` に指定します。新規に設定を開始する場合は、`scope` を `drive.file` に指定し、本アプリが作成したファイルのみにアクセス制限することを推奨します。
Google Drive の認証情報は各マシンの `~/.config/rclone/rclone.conf` に保存され、本リポジトリや workflow 用リポジトリには含まれません。

### rclone の共有 OAuth クライアントから移行する場合

rclone の共有 OAuth クライアントは 2026 年中に廃止予定のため、個人の client_id と client_secret を取得して使用してください（詳細は [rclone 公式手順](https://rclone.org/drive/#making-your-own-client-id) を参照）。
共有クライアントで作成した既存ファイルは、新しいクライアントで `scope` を `drive.file` に設定した場合、見えなくなることがあります。そのため、移行後の新しいクライアントでは `scope` を `drive`（Drive 全体の読み書き・削除権限）に指定して認可を行ってください。
本番接続とは別接続で既存の添付ファイルや文献のハッシュを照合し、本番用の認証情報を退避してから切り替えます。リモート名、同期先ディレクトリ、同期履歴（baseline）に変更がない場合、認証情報の変更だけで再同期（resync）を行う必要はありません。
なお、OAuth 同意画面の設定が「Testing」のままだと認可の有効期限が 7 日間で切れてしまうため、継続利用する場合は公開ステータス（In production）になっているか確認してください。

### 初回同期について

同期履歴が存在しない初回実行時に限り、`bisync` に `--resync` オプションが必要です。スクリプトは以下の通り状況に応じて自動分岐します：

- Drive 側が空または未存在: Drive 側にフォルダを作成して `--resync` を実行
- ローカル側が空で Drive 側にデータが存在: Drive 側のデータを取り込む
- ローカルと Drive の両方にデータが存在: 誤って異なる内容を混合・上書きするのを防ぐため処理を停止

両方にデータが存在して停止した場合は、該当する Drive 側とローカル側の双方の中身を確認した上で、対象を絞って明示的に実行してください（文献データのみの場合は `--only papis`）。

```sh
MEMEX_FORCE_RESYNC=1 memex-sync --only attachments --resync
```

## 日常的な運用

ファイル変更検知による自動同期と 15 分ごとの定期実行により、バックグラウンドで自動同期されます。他のマシンで追加されたファイルは、次の同期タイミングで自動的に取り込まれます。

```sh
memex-sync                 # 設定済みの全対象を同期
memex-sync --only papis    # papis のみを同期
memex-sync --dry-run       # 以降の引数は rclone bisync にそのまま渡される（テスト実行）
journalctl --user -u attachments-sync -f
journalctl --user -u papis-sync -f
journalctl --user -u originals-sync -f
```

※同期先は設定ファイルで定義されているため、コマンド引数で変更することはできません。
ファイルの削除も双方向に反映されます。誤削除防止として、Google Drive のごみ箱（30 日間保持）および `bisync` の `--max-delete` オプション（デフォルトでは 50% を超える大量削除で安全停止）により保護されています。

添付ファイルについて、Obsidian 内では通常通り画像を貼り付けます（`Assets/attachments` に保存されます）。

## トラブルシューティング

エラーが発生した場合は対処方法が画面に表示されるため、まずはその指示に従ってください。

- `remote 'gdrive' が未定義です`: `rclone config` でリモート設定を作成してください（`memex-setup` の案内に従う）。
- `認証に失敗しました`: 認証トークンの期限が切れています。`rclone config reconnect gdrive:` を実行して再認証してください。
- `両側にデータがあります` または `--resync` で停止する: 同期履歴が喪失しているか、異なる内容同士を統合しようとしています。双方のデータ内容を確認・バックアップした上で、対象を `--only` で絞り、`MEMEX_FORCE_RESYNC=1` を付与して再実行してください。
- systemd unit が inactive のまま動かない: 対象ディレクトリがまだ存在しないためです。`ConditionPathIsDirectory` により正常にスキップされている状態であり、エラーではありません。
- `.conflict` というファイルが生成された: 2 台の端末で同時に同じファイルが更新されました。内容を確認し、正しい方のファイルを残してください。
- トークン書き戻し（writeback）の警告が表示される: rclone が更新されたアクセストークンをファイルに保存している通知であり、失効エラーではありません。

## Originals の運用

両方の PC で初期設定が完了しており、`services.memex.originals.autoSync = true` が設定されています。ファイル変更検知および 15 分周期で `originals-sync` が動作し同期されます。
削除されたり上書きされた古いバージョンは、`${XDG_DATA_HOME:-$HOME/.local/share}/memex/originals-backups/<host>/<runid>` および `gdrive:memex-originals-backups/<host>/<runid>` へ自動的に退避されます。退避されたファイルを直接同期対象ディレクトリへ書き戻さないでください。

新しい PC を追加する場合は、該当 PC の `autoSync` を一時的に `false` に設定し、先に初期化を行います。

1. 両 PC および Drive 内のデータを確認し、既存データを同期対象外の安全な場所へ退避します。両方に同名で異なる内容のファイルが存在する場合は、あらかじめ整理しておきます。
2. もう一方の PC で Originals の同期を停止した状態で、`memex-sync --only originals --resync --dry-run` を実行して事前確認し、問題がなければ `--dry-run` を外して初期化を実行します。
3. もう一方の PC でも同様に差分確認・退避を行ってから初期化を実行し、以降は `memex-sync --only originals` で同期を行います。
4. 両 PC にて、ファイルの新規追加・同名競合・削除/上書き時の退避と復元・中断・二重実行・オフライン復帰の動作を検証・確認できた後、`autoSync` を `true` に変更して有効化します。

競合が発生した場合、両方のバージョンが別名で保存されることがあります。ログを確認の上、採用する方を元のファイル名に戻すか、ノート側のリンク記述を修正してから再度同期してください。
誤って削除・上書きしたファイルを復元する場合は、両 PC の自動同期を一度停止させ、指定世代の退避データを同期先に戻して内容を照合・確認してから同期を再開してください。退避データ自体は削除せずに保持しておきます。
同期履歴データが破損した場合は、焦って `resync` を実行せず、必ず実データと退避データの安全を確保してから手動で状態を判断してください。
強制終了等で残留したロックは送信後約 2 分で自動解除され、次回の同期時に直前の成功した履歴から復旧を試みます。復旧に失敗した場合は処理が停止するため、原因を調べてください。

ワークフロー（workflow）の変更・試行を行う際は、`--override-input memex-nix path:/path/to/memex-nix` で評価を行い、`flake.lock` の更新作業とは分離して実施してください。
