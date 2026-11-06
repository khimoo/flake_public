# memex の Google Drive 同期

vault の画像や PDF などのバイナリは、中身を git-annex で Google Drive に置き、Git には所在だけを入れます。ノートは今までどおり Git で同期します。

機能フラグ `memexSync` で有効になります。`nixos-desktop` と `nixos-spin713` では有効です。スタンドアロンの home-manager 環境では、ユーザーごとの home モジュールで `local.profile.features` と `local.profile.memexRoot` を設定してください。現在の vault プロファイルは Linux 環境にのみ対応しています。

設計ドキュメント: [memex の Google Drive 同期の設計](../architecture/memex-drive-sync.md)

## 保存先の決まり方

- バイナリ（画像、PDF など）: git-annex に入り、中身は Drive に置かれます。置き場所は関係ありません。
- テキスト（ノートなど）と `.obsidian/` の中: Git に入ります。
- `.gitignore` に書いたもの: その PC だけに置かれます。ただし、既に Git で追跡しているファイルには効きません。その場合は `git rm --cached <ファイル>` で追跡から外して commit してください（`memex-sync` が該当するファイルを知らせます）。

この規則は vault の `.gitattributes` にあります。普通に `git add`（Obsidian の vault backup も同じ）すれば振り分けられます。

## 新しいマシンでの初期設定手順

1. `switch` を実行します（vault がクローンされ、git-annex と同期用の systemd unit が入ります）。
2. `memex-setup` を実行します。rclone の接続を確かめ、vault の git-annex を初期化し、Drive の保存先を有効にします。
3. `memex-sync` を実行すると、バイナリの中身が Drive から届きます。

`rclone config` では、リモート名を `gdrive`、`Storage` を `drive` にします。
Google Drive の認証情報は各マシンの `~/.config/rclone/rclone.conf` に保存され、このリポジトリや memex-nix には含まれません。

### rclone の共有 OAuth クライアントから移行する場合

rclone の共有 OAuth クライアントは 2026 年中に廃止予定のため、個人の client_id と client_secret を取得して使用してください（詳細は [rclone 公式手順](https://rclone.org/drive/#making-your-own-client-id) を参照）。
共有クライアントで作成した既存ファイルは、新しいクライアントで `scope` を `drive.file` に設定した場合、見えなくなることがあります。そのため、移行後の新しいクライアントでは `scope` を `drive`（Drive 全体の読み書き・削除権限）に指定して認可を行ってください。
OAuth 同意画面の設定が「Testing」のままだと認可の有効期限が 7 日間で切れてしまうため、継続利用する場合は公開ステータス（In production）になっているか確認してください。

## 日常的な運用

ファイルを置き、ノートを書いて、いつもどおり commit します。commit、pull のたびと 15 分ごとに `memex-sync` が動き、バイナリの中身を Drive と各 PC の間で同期します。

```sh
memex-sync                          # 今すぐ同期
git annex whereis <ファイル>         # 中身がどこにあるか
journalctl --user -u memex-sync -f
```

貼り付けた画像が Drive に届くのは、commit した後です。
中身がまだ届いていない PC では、そのファイルは所在を書いた短いテキストに見えます。次の同期で中身が届きます。

削除したファイルや古い版の中身も Drive に残ります。戻すときは、Git の履歴からファイルを戻して `git annex get <ファイル>` を実行します。

## 規則を変えたとき

`.gitattributes` を変えて commit すると、各 PC の `memex-sync` が、既にあるファイルのうち規則と違う側にあるものを移し、そのファイルだけを commit します。push は vault backup で行ってください。
編集中のファイルと、中身がまだ届いていないファイルは、次の同期まで移しません。

## トラブルシューティング

- `git-annex で初期化されていません` / `保存先 'gdrive' がこの PC で有効になっていません`: `memex-setup` を実行してください。
- `remote 'gdrive' が未定義です`: `rclone config` でリモート設定を作成してください。
- `認証に失敗しました`: `rclone config reconnect gdrive:` を実行して再認証してください。
- `保存先の規則を評価できなかった`: 表示されたファイルの種類を git-annex が判定できませんでした。中身の同期は行われています。ファイルを確認してください。
- `.gitignore に当たるが Git で追跡中`: そのファイルは他の PC にも配られています。その PC だけに置くなら、表示どおり `git rm --cached` で追跡から外して commit してください。
- Git の操作で `git-annex: command not found` が出る: git-annex が PATH に無い環境で vault を操作しています。switch 後のシェルか Obsidian から操作してください。

memex-nix の変更を試すときは、`--override-input memex-nix path:/path/to/memex-nix` で評価し、`flake.lock` の更新とは分けてください。
