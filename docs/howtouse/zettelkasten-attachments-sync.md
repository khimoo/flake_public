# Zettelkasten の Google Drive 同期（使い方）

Vault 直下の `attachments/`（添付ファイル）と `references/`（papis ライブラリ）を Google Drive と双方向同期します。実体ファイルはローカル側にも保持したまま、rclone bisync を用いてミラーリングします。なお、Git にはバイナリ（blob）を含めないよう、Vault の `.gitignore` で両フォルダを除外しています。

同期の実行コマンドは `zettelkasten-sync` に一本化されています。どの項目を同期するかは home-manager の options で設定します。
papis 固有の使い方については [papis-gdrive-sync.md](./papis-gdrive-sync.md) を、設計上の判断については [../architecture/zettelkasten-attachments-sync.md](../architecture/zettelkasten-attachments-sync.md) を参照してください。

## 対応環境

| feature | 同期対象 | Drive 側 |
|---|---|---|
| `zettelkastenSync` | `<vault>/attachments` | `gdrive:zettelkasten-attachments` |
| `referenceSync` | `<vault>/references` | `gdrive:papis-library` |

NixOS ホスト（`nixos-desktop`、`nixos-spin713`）では両方の機能が有効になっています。standalone home-manager では、個人の home モジュール側で `local.profile.features` と `local.profile.zettelkastenRoot` を指定してください。デフォルトでは同期サービスは有効になりません。なお、現在の Vault プロファイルは Linux 限定です。

## 認証（rclone）

Google Drive の OAuth トークンは宣言的には生成できないため、**各マシンの `~/.config/rclone/rclone.conf` で個別に管理します**。flake_public や workflow repo には認証情報を持たせません（以前は sops で暗号化した rclone.conf を workflow repo に配置していましたが、現在は廃止されています）。

リモート名は `gdrive` です（`services.zettelkasten.rcloneRemote` のデフォルト値）。

## 新しいマシンのセットアップ

```sh
# 1. switch する（vault が clone され、Obsidian 設定が配置され、同期の unit が入る）
sudo nixos-rebuild switch --flake .#<hostname>

# 2. 残りを対話で片付ける
zettelkasten-setup
```

`zettelkasten-setup` で確認される項目は以下の2点のみです:

1. **Google Drive との接続確認** — リモート `gdrive` に接続できない場合は `rclone config` を起動します。リモート名は必ず `gdrive` にしてください（options の設定と一致していないと正しく動作しません）。`Storage` には `drive` を指定します。新規運用の場合は `scope` を **`drive.file`** に設定し、このアプリが作成したファイルのみにアクセス権限を絞り込みます。既存の共有クライアントから専用クライアントへ移行する場合は、後述の「専用OAuthへの移行」を参照してください。
2. **初回同期** — そのまま `zettelkasten-sync` を実行します。

途中で処理を中断した場合でも、再実行すれば処理済みの箇所は自動的にスキップされます。個別の進捗ファイルは保持せず、実態（rclone リモートや bisync の同期履歴）を直接参照して状態を判断します。

### 専用OAuthへの移行

rclone の共有 OAuth クライアントは 2026 年中に提供終了予定のため、専用の client_id / client_secret を使用します。
既存の共有アプリで作成したファイルは、新規アプリの `drive.file` スコープからは認識できない場合があります。
そのため、今回の移行では `scope = drive` を指定し、利用者が **Drive 全体の読み書き・削除権限** を付与・認可します。
本番環境とは別の接続を用いて既存の添付ファイルや文献リストのハッシュ値を照合し、本番の認証情報をバックアップした上で切り替えを行います。
リモート名、同期先、および baseline（同期履歴）はそのまま維持し、認証情報の変更だけを理由とした再同期（resync）は行いません。
なお、同意画面のステータスを「Testing」のままにしておくと認可が通常7日で失効してしまうため、継続して運用する場合は公開状態も併せて確認してください。
[rclone公式手順](https://rclone.org/drive/#making-your-own-client-id)

### 初回同期の挙動

bisync では、同期履歴（baseline）が存在しない初回のみ `--resync` が必要です。履歴が存在しない場合の処理分岐は自動的に行われるため、手動で `--resync` を指定する必要はありません:

| ローカル | Drive | 挙動 |
|---|---|---|
| 空、またはファイルが存在する | 空 / 未作成 | Drive 側にフォルダを作成して resync を実行 |
| 空 | データあり | Drive の内容を取り込む（ローカル側のデータ消失リスクがないため自動処理） |
| データあり | データあり | **処理を停止**。内容の異なる2つのデータソースを誤って統合するのを防ぐため |

上記の表は attachments および papis の挙動です。最後のケース（双方にデータが存在する場合）のみ、エラーとなった対象の Drive とローカルの内容を確認した上で、対象を限定して対応します。以下は添付ファイルの場合の例です（文献の場合は `--only papis`）:

```sh
ZK_FORCE_RESYNC=1 zettelkasten-sync --only attachments --resync
```

## 日常運用

同期は自動的に実行されます。ローカルの変更を検知して即座に同期する仕組みと、同期漏れを防止する定期実行（デフォルトは15分間隔）の2系統で構成されています。他のマシンで追加されたファイルは、自身の次回同期時に pull されます（リアルタイム反映ではありません）。

手動で実行する場合:

```sh
zettelkasten-sync                 # 設定どおり全部
zettelkasten-sync --only papis    # papis だけ
zettelkasten-sync --dry-run       # 以降の引数は rclone bisync へ素通し
```

同期先は options 側で固定設定されているため、コマンドの引数で変更することはできません。

ログの確認:

```sh
journalctl --user -u zettelkasten-sync -f     # 添付（Linux）
journalctl --user -u papis-sync -f            # papis（Linux）
# macOS: ~/Library/Logs/{zettelkasten-sync,papis-sync}.log
```

ファイルの削除は双方向に反映されます。安全対策として、Google Drive のゴミ箱機能（30日間は復元可能）と、bisync の `--max-delete` オプション（デフォルトでは50%を超える削除が発生した場合に処理を中断）が用意されています。

## 添付を貼る

- Obsidian: 通常通り貼り付けます（`attachmentFolderPath=attachments` に保存されます）。
- Neovim: Markdown ファイル上で `<leader>p` を押します（img-clip により Vault ルートの `attachments/` に保存されます）。

どちらのエディタを使用しても、同じ単一のフォルダへ保存されます（詳細は [markdown プラグインのドキュメント](../../modules/home-manager/dev/neovim/config/docs/plugins/markdown.md) を参照）。

## トラブルシューティング

エラー発生時は復旧手順を含んだメッセージが出力されますので、まずはその指示に従ってください。

| 症状 | 原因 / 対処 |
|---|---|
| `remote 'gdrive' が未定義です` | `rclone config` でリモートを作成します（`zettelkasten-setup` の案内に従ってください）。 |
| `認証に失敗しました` | トークンが失効しています。`rclone config reconnect gdrive:` を実行してください。 |
| `両側にデータがあります` | 同期履歴の喪失か、別々の内容を統合しようとしています。内容を確認した上で `ZK_FORCE_RESYNC=1 zettelkasten-sync --only attachments --resync` を実行してください。 |
| `--resync が中止される` | 既存の同期履歴が存在します（誤上書きの防止）。内容の確認・バックアップ後、失敗した対象を `--only` で絞り込み、意図して再同期する場合のみ `ZK_FORCE_RESYNC=1` を指定して実行してください。 |
| ユニットが inactive のまま | 対象ディレクトリが未作成です。`ConditionPathIsDirectory` によりスキップされている状態です（エラーではありません）。 |
| `.conflict` ファイルが生成される | 2台のマシンから同時に更新されました。ファイル内容を確認し、正しい方を残してください。 |
| トークン書き戻しに関する警告（warning） | rclone がリフレッシュ後のアクセストークンを書き戻しているだけです。リフレッシュトークン自体は長期間有効なため、この警告だけで失効と判断する必要はなく、無視して問題ありません。 |

## Originalsの導入と復旧

Originals 対応の workflow input を取り込んだ構成で使用します。ソースコードを編集しただけでは、flake.lock に固定されたバージョンや導入済みのコマンドは更新されません。評価時のローカル検証には `--override-input zettelkasten path:/path/to/zettelkasten-workflow` を使用し、lock ファイルの変更作業とは切り離して検証してください。

`zettelkastenSync` が有効な場合、Originals もコマンドの同期対象に含まれます。現在は両 PC ともに初期化を完了しており、`services.zettelkasten.originals.autoSync = true` に設定されています。この構成を反映すると `originals-sync.service`・`.path`・`.timer` が生成され、ローカルの変更検知時および 15 分間隔で同期が行われます。
新しい PC を導入する際は、その PC の autoSync を false に設定した上で、先に以下の初期化手順を実施してください。
なお、原本は `<vault>/Originals`、Drive 側の同期先は `gdrive:zettelkasten-originals` です。
バックアップの退避先は `${XDG_DATA_HOME:-$HOME/.local/share}/zettelkasten/originals-backups/<host>/<runid>` および `gdrive:zettelkasten-originals-backups/<host>/<runid>` となります。退避したデータを同期対象ディレクトリへ直接戻さないでください。

1. 両方の PC と Drive の内容を比較し、同期対象外の場所へ元データを退避します。両側に同名で内容が異なるファイルがある場合は、あらかじめ整理しておきます。
2. もう一方の PC の Originals ジョブを停止した状態で、担当 PC で `zettelkasten-sync --only originals --resync --dry-run` を実行して動作を確認し、問題がなければ `--dry-run` を外して初期化を実行します。
3. もう一方の PC でも同様に内容の比較と退避を済ませてから初期化を行い、以降は `zettelkasten-sync --only originals` で同期します。
4. 隔離された Drive のテスト環境を用いて、両 PC それぞれでのファイル追加、同名ファイルの競合、削除・上書き時の退避と復元、中断、多重実行、オフラインからの復帰を確認した上で、autoSync を有効化します。

競合が発生した場合、双方のバージョンが別名で保存されることがあります。その際はログを確認し、採用する方を元のファイル名に戻すか、ノート側のリンクを修正した上で同期してください。
誤った削除や上書きから復元する場合は、両 PC の自動同期を一時停止し、該当世代のバックアップを通常の同期先へ復元して内容を照合した上で、順次同期を行います。退避された世代データ自体は削除せずそのまま保持してください。
同期履歴が破損した場合は、安易に resync を行わず、実データと退避データの安全を確保してから手動で対処を判断してください。

Originals では `--recover --max-lock 2m` を使用します。強制中断などでロックが残ってしまった場合でも、最終更新から約2分でロックが期限切れとなり、次回の通常同期時に直近の成功履歴から復旧を試みます。
なお、同期スクリプト側にはロックを自動削除する処理や自動 resync を行う処理は実装していません。履歴の欠損や復旧の失敗が発生した場合は、処理を停止して原因を調査してください。
詳細については、[rcloneの復旧仕様](https://rclone.org/bisync/#recover) および [ロック期限の仕様](https://rclone.org/bisync/#max-lock) を参照してください。

通常同期のログは `zettelkasten-sync --only originals` のコマンド出力から、自動化後は `journalctl --user -u originals-sync` で確認できます。なお、ここでの退避処理は独立したバックアップとは異なるため、必要に応じて既存のバックアップ対象に Originals も含めてください。
