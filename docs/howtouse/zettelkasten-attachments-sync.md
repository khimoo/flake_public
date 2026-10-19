# Zettelkasten の Google Drive 同期（使い方）

vault 直下の `attachments/`（添付）と `references/`（papis ライブラリ）を Google Drive と
双方向同期する。実体はローカルにも残し、rclone bisync でミラーする。git には blob を載せない
（vault の `.gitignore` が両方を除外している）。

同期の入口は `zettelkasten-sync` 1 本。何が同期されるかは home-manager の options が決める。
papis 固有の使い方は [papis-gdrive-sync.md](./papis-gdrive-sync.md) を参照。
設計判断は [../architecture/zettelkasten-attachments-sync.md](../architecture/zettelkasten-attachments-sync.md) を参照。

## 対応環境

| feature | 同期対象 | Drive 側 |
|---|---|---|
| `zettelkastenSync` | `<vault>/attachments` | `gdrive:zettelkasten-attachments` |
| `referenceSync` | `<vault>/references` | `gdrive:papis-library` |

NixOS ホスト（`nixos-desktop`, `nixos-spin713`）は両方有効。standalone home-manager は
本人のhomeモジュールで `local.profile.features` と `local.profile.zettelkastenRoot` を指定する。既定では同期サービスを有効にしない。現在のvaultプロファイルはLinux限定。

## 認証（rclone）

Google Drive の OAuth トークンは宣言的に作れないので、**各マシンの
`~/.config/rclone/rclone.conf` に委ねる**。flake_public も workflow repo も認証情報を持たない
（以前は sops で暗号化した rclone.conf を workflow repo に置いていたが、廃止した）。

remote 名は `gdrive`（`services.zettelkasten.rcloneRemote` の既定）。

## 新しいマシンのセットアップ

```sh
# 1. switch する（vault が clone され、Obsidian 設定が配置され、同期の unit が入る）
sudo nixos-rebuild switch --flake .#<hostname>

# 2. 残りを対話で片付ける
zettelkasten-setup
```

`zettelkasten-setup` が聞くのは 2 つだけ:

1. **Google Drive との接続確認** — remote `gdrive` に繋がらなければ `rclone config` を開く。
   remote 名は `gdrive` にすること（options と一致していないと動かない）。
   `Storage` は `drive`。新規運用の `scope` は **`drive.file`** とし、このアプリが作った
   ファイルに権限を限定する。既存共有クライアントから専用クライアントへ移行する場合は、
   下の「専用OAuthへの移行」を参照する。
2. **初回同期** — そのまま `zettelkasten-sync` を実行する。

途中で止めても、もう一度実行すれば済んだところは飛ばす。進捗ファイルは持たず、実物
（rclone remote / bisync の記録）を見て判断する。

### 専用OAuthへの移行

rcloneの共有OAuthクライアントは2026年中に停止予定のため、専用client_id/client_secretを使う。
既存共有アプリが作ったファイルは、新しいアプリの `drive.file` では見えない場合がある。
今回の移行では `scope = drive` を使用し、**Drive全体の読み書き・削除権限**として利用者が認可する。
本番とは別の接続で既存添付・文献の一覧とハッシュを照合し、本番認証を退避してから切り替える。
remote名・同期先・baselineを維持し、認証変更だけを理由にresyncしない。
同意画面をTestingのままにすると認可が通常7日で失効するため、継続運用では公開状態も確認する。
[rclone公式手順](https://rclone.org/drive/#making-your-own-client-id)

### 初回同期の挙動

bisync は「同期の記録」（baseline）が無い初回だけ `--resync` が要る。記録が無いときの
分岐は自動で、手で `--resync` を打つ必要は無い:

| ローカル | Drive | 挙動 |
|---|---|---|
| 何でも | 空 / 未作成 | Drive 側にフォルダを作って resync する |
| 空 | データあり | Drive の内容を取り込む（失うものが無いので自動） |
| データあり | データあり | **止まる**。中身の違う 2 つを合流させようとしている可能性があるため |

上表はattachments/papisの挙動。最後のケースだけ、失敗した対象のDriveとローカルを確認して対象を限定する。添付の例（文献なら `--only papis`）:

```sh
ZK_FORCE_RESYNC=1 zettelkasten-sync --only attachments --resync
```

## 日常運用

同期は自動で走る。ローカルの変更を検知する経路と、取りこぼしを拾う定期実行（既定 15 分）の
2 本立て。他マシンの追加は、次に自分が同期したときに pull される（リアルタイムではない）。

手で走らせるとき:

```sh
zettelkasten-sync                 # 設定どおり全部
zettelkasten-sync --only papis    # papis だけ
zettelkasten-sync --dry-run       # 以降の引数は rclone bisync へ素通し
```

同期先は options が持っていて、引数では変えられない。

ログ:

```sh
journalctl --user -u zettelkasten-sync -f     # 添付（Linux）
journalctl --user -u papis-sync -f            # papis（Linux）
# macOS: ~/Library/Logs/{zettelkasten-sync,papis-sync}.log
```

削除は双方向に伝播する。安全網は Drive のゴミ箱（30 日は復元可）と bisync の `--max-delete`
（既定 50% 超で中断）。

## 添付を貼る

- Obsidian: 通常どおり貼り付ける（`attachmentFolderPath=attachments` に保存される）
- Neovim: Markdown で `<leader>p`（img-clip が vault ルートの `attachments/` に保存）

どちらも同じ 1 フォルダに着地する
（[markdown プラグインのドキュメント](../../modules/home-manager/dev/neovim/config/docs/plugins/markdown.md)）。

## トラブルシューティング

エラーは復旧手順つきで出るので、まずそのメッセージに従う。

| 症状 | 原因 / 対処 |
|------|-------------|
| `remote 'gdrive' が未定義です` | `rclone config` で remote を作る（`zettelkasten-setup` が案内する） |
| `認証に失敗しました` | token 失効。`rclone config reconnect gdrive:` |
| `両側にデータがあります` | 記録の喪失か、別々の中身を合流させようとしている。確認して `ZK_FORCE_RESYNC=1 zettelkasten-sync --only attachments --resync` |
| `--resync が中止される` | 記録が既存（誤上書き防止）。内容確認・退避後、失敗対象を `--only` で限定し、意図的な場合だけ `ZK_FORCE_RESYNC=1` |
| unit が inactive のまま | 対象ディレクトリが未作成。`ConditionPathIsDirectory` で skip される（失敗ではない） |
| `.conflict` ファイルが出る | 2 台が同時に更新した。中身を見て正しい方を残す |
| token 書き戻しの warning | rclone が refresh 後の access token を書き戻すだけ。refresh token は長命なので無視してよい |

## Originalsの導入と復旧

Originals対応のworkflow inputを取り込んだ構成で使う。ソース編集だけではflake.lockに
pinされた版や導入済みコマンドは変わらない。評価時のローカル検証は
`--override-input zettelkasten path:/path/to/zettelkasten-workflow` を使い、lockファイルの変更とは分ける。

`zettelkastenSync` 有効時にOriginalsもコマンド対象となる。現在は両PCの初期化を済ませ、
`services.zettelkasten.originals.autoSync = true` としている。構成を反映すると
`originals-sync.service`・`.path`・`.timer` が生成され、ローカル変更時と15分間隔で同期する。
新しいPCを導入するときは、そのPCのautoSyncをfalseにして以下の初期化を先に行う。
原本は `<vault>/Originals`、Drive同期先は `gdrive:zettelkasten-originals`。
退避先は `${XDG_DATA_HOME:-$HOME/.local/share}/zettelkasten/originals-backups/<host>/<runid>`
と `gdrive:zettelkasten-originals-backups/<host>/<runid>`。同期対象へ退避物を戻さない。

1. 両PCとDriveの内容を比較し、同期外へ元データを退避する。両側に同名異内容があれば先に整理する。
2. 他方のOriginalsジョブを動かさず、担当PCで `zettelkasten-sync --only originals --resync --dry-run` を確認後、同じコマンドからdry-runを外して初期化する。
3. 他方PCも内容比較・退避を済ませて初期化し、以後は `zettelkasten-sync --only originals` で同期する。
4. 隔離したDrive試験先で両PC追加、同名競合、削除・上書きの退避と復元、中断、重複実行、オフライン復帰を確認してからautoSyncを有効化する。

競合した両版は別名になる場合がある。ログを読み、採用版を元の名前へ戻すかノートのリンクを
修正して同期する。削除・上書きから戻すときは両PCの自動同期を一旦止め、該当世代の版を
通常同期先へ復元して内容を照合し、順に同期する。退避世代そのものは削除せず保持する。
履歴が壊れた場合は無条件にresyncせず、実データと退避を確保してから手動判断する。

Originalsは `--recover --max-lock 2m` を使う。強制中断時に残るロックは最後の更新から
約2分で期限切れとなり、次の通常同期が直近の成功履歴から復旧を試みる。
ロックの自動削除や自動resyncは行わない。履歴欠損・復旧失敗は停止して調査する。
[rcloneの復旧仕様](https://rclone.org/bisync/#recover)と
[ロック期限の仕様](https://rclone.org/bisync/#max-lock)を参照。

通常同期のログは `zettelkasten-sync --only originals` の出力、自動化後は
`journalctl --user -u originals-sync` を確認する。退避は独立バックアップとは別なので、
必要なら既存バックアップ手段へOriginalsも含める。
