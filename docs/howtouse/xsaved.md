# X のいいねとブックマークの保存と意味検索

X で「いいね」またはブックマークしたツイートを、本文・画像・動画・引用元を含めてローカルに保存し、自然言語による検索や類似ツイートの検索を行えるようにします。
ツール本体は、プライベートリポジトリ [khimoo/xsaved](https://github.com/khimoo/xsaved) の `~/sagyo/xsaved` にあるチェックアウトを利用します。コマンド一覧は本体の README を参照してください。
nixos-desktop の pomu 環境では `clone-repos` の対象に含まれます。新しい環境のセットアップ手順は [SSH 鍵の配布と private repo の clone](private-repo-clone.md) を、保存済みツイートと DB の復元方法は「[バックアップ](#バックアップ)」を参照してください。

設定箇所は [home-manager-pomu.nix](../../hosts/nixos-desktop/home-manager-pomu.nix) の `local.xsaved` です。

設計ドキュメント: [X のいいねとブックマークの保存の設計](../architecture/xsaved.md)

## 初回準備

データは SATA SSD のサブボリューム `@xsaved` に保存します。
サブボリュームは自動作成されないため、[disk-tiering.md の「新しい subvol の追加手順」](./disk-tiering.md#新しい-subvol-の追加手順) の手順に従って事前に作成してください。
`@xsaved` 固有の作成手順は以下の通りです。

```sh
sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
sudo nix shell nixpkgs#btrfs-progs -c btrfs subvolume create /mnt/sda/@xsaved
sudo chown pomu:users /mnt/sda/@xsaved
sudo umount /mnt/sda
sudo nixos-rebuild switch --flake .#nixos-desktop
```

マウント設定に `nofail` オプションを指定しているため、サブボリューム作成前に switch や再起動を行ってもシステムの起動は妨げられません。
作成前に switch や再起動をした場合は、サブボリューム作成後に再起動するか、以下のコマンドでマウントしてください。

```sh
sudo systemctl start home-pomu-.local-share-xsaved.mount
```

いいねを取得したい X のアカウント名（`@` を除いた文字列）を、データディレクトリ内の `x-user` ファイルに書き込みます。
このリポジトリは公開設定になっているため、アカウント名は Nix の設定ファイルに直接記述しないでください。

```sh
echo <アカウント名> > ~/.local/share/xsaved/x-user
```

いいねとブックマークの取得には Firefox のログイン情報（cookie）を使用するため、あらかじめ Firefox で X にログインしておいてください。ブックマークはログイン中のアカウントから取得します。

最初に `xsaved` を実行した際、uv が Python や ROCm 版 PyTorch などをデータディレクトリへダウンロードします（数 GB 程度）。
最初の `xsaved sync` 実行時はローカルにデータが一切存在しないため、いいね欄とブックマーク欄を、X 側の一覧で取得可能な最も古いデータまで遡って取得します。
なお、ブックマークは公式アーカイブに含まれないため、一覧に表示されない古いデータは取得できません（本体の `TODO.md` 参照）。

## 使い方

```bash
xsaved search '鶏肉の焼き方'
xsaved search '鶏肉の焼き方' --source bookmarks
xsaved similar <ツイートID>
xsaved status
xsaved delete <ツイートID>
xsaved fetch likejs <公式アーカイブの like.js>
xsaved retry
```

`search` と `similar` は、デフォルトでいいねとブックマークの両方を対象に検索します。`--source likes` または `--source bookmarks` を指定すると、片方のみに絞り込んで検索できます。
`xsaved delete` は、対象ツイートがいいねとブックマークのどちらに登録されているかにかかわらず、ローカルに保存されたデータを丸ごと削除します。なお、X 側でいいねやブックマークを解除しても、ローカルの保存データは自動削除されず残ります。
`xsaved retry` は、取得できなかった返信先、引用元、like.js のいいねと、欠けている画像や動画を取得し直します。定期実行には含まれないため、`xsaved status` の `incomplete_media`（画像や動画が欠けているツイートの数）が増えたときなどに手動で実行してください。

引数は xsaved の README に記載されているコマンドと同様で、`python -m xsaved` を `xsaved` に置き換えて使用します。
`xsaved-env` を引数なしで実行すると専用環境のシェルに入り、引数を指定して実行するとそのコマンドのみを環境内で実行します。

`xsaved` は `~/sagyo/xsaved` で現在チェックアウトされているバージョンを実行します。ブランチを切り替えると、定期実行処理も切り替え先のバージョンで動作します。

## Web UI

nixos-desktop のブラウザで <http://xsaved.localhost/> を開くと、検索および類似ツイートの検索機能を利用できます。
「検索対象」で「すべて」「いいね」「ブックマーク」を選択でき、選択した対象は「似たツイート」と「もっと表示」にも引き継がれます。
検索を実行すると、ruri（本文＋OCRテキスト）、Qwen（本文＋OCRテキスト）、Qwen（画像）、全文検索の結果が、それぞれ独立した列に並んで表示されます。全文検索ではスペース区切りで AND 検索、`OR` 区切りで OR 検索が可能です。
いずれの列でも、引用元の本文や画像がヒットした場合は、それを引用している保存ツイートが表示されます。本文の列では保存ツイートと引用元を個別に比較します。全文検索では両方のテキストを結合して検索するため、検索語がそれぞれのツイートに分かれて含まれていても検出できます。
検索結果のツイートにある「似たツイート」ボタンを押すと、そのツイートに類似した保存ツイートを、全文検索を除く 3 つの列で検索します。
各列は独立してスクロールでき、「もっと表示」をクリックするとその列の続きを 20 件ずつ追加読み込みできます。古い検索結果の続きを取得できなくなった場合は、検索し直してください。

サーバーは常駐しません。アクセス時に systemd ソケット経由で起動し、15 分間リクエストがないと自動停止します。
サーバー起動後の初回検索では毎回埋め込みモデルを GPU に読み込むため、1 分以上かかります。読み込み完了後は、停止するまで 2 秒前後でレスポンスが返ります。
夜間に `xsaved-process` が埋め込み計算を行っている間は、モデルを使用する 3 列に「GPU を使うほかの計算（夜間の埋め込みなど）が終わるまで、モデルを使う検索はできません。」と表示されます。この間も全文検索の列と類似ツイート検索は利用可能です。
反対に、検索サーバーが動いている間に 4:00 を迎えると、`xsaved-process` は検索サーバーが停止するまで（最後のリクエストから最大 15 分）埋め込み計算の開始を待ちます。
サーバーが停止すると、モデルが占有していた VRAM も解放されます。

```bash
systemctl --user status xsaved-web.socket xsaved-web-server
journalctl --user -u xsaved-web-server
systemctl status caddy
journalctl -u caddy
```

アクセスできるのは自マシンからのみです。URL は `http://` を指定してください。
Caddy が動作していない場合は <http://127.0.0.1:8765/> から直接接続して問題を切り分けられます。
内部の接続先ポートは `local.xsaved.webPort` で変更できます。Caddy の転送先もこれに追従し、サーバー本体はその次のポートで待機します。

## 定期実行

以下の systemd ユーザータイマーを設定しています。なお `xsaved-backup` は `local.xsaved.backup.repository` を設定した場合のみ有効化されます。

| タイマー | 実行時刻 | 実行内容 |
|-------|------|-------------|
| `xsaved-sync` | 毎時 0 分 | `xsaved sync`（いいね欄とブックマーク欄、返信先と引用元の取得と登録） |
| `xsaved-process` | 毎日 4:00 | `xsaved embed text` → `ocr` → `embed images` → `embed text` の順で実行 |
| `xsaved-backup` | 毎日 6:00 | 取得したツイートとデータベースを restic で同期（後述の「バックアップ」参照） |

`xsaved-sync` と `xsaved-process` は、実行開始時に `xsaved migrate` を行うため、xsaved を更新してデータベーススキーマが変更された場合も次回実行時に自動適用されます。
`xsaved-process` は途中のステップで失敗しても残りの処理を継続し、最後に失敗ステータスで終了します。
各タイマーが失敗した場合は GNOME 上に通知が表示されます（[failure-notify.md](./failure-notify.md)）。
電源オフなどで 4:00 や 6:00 の実行タイミングを逃した場合は、次回のシステム起動時に実行されます。
nixos-desktop の pomu ユーザーは linger を有効化しているため、ログインしていなくても全タイマーが動作します。linger が無効なユーザーの場合はログイン中のみ動作し、逃した分は次回ログイン時に実行されます。

```bash
systemctl --user list-timers 'xsaved-*'
journalctl --user -u xsaved-sync -u xsaved-process
xsaved status
```

`xsaved-process` は新規取り込み件数が多いと完了まで数時間かかることがあります。
GPU を消費する他のアプリと競合した場合は途中で停止しても問題ありません。
OCR や埋め込み計算は 1 件ごとに進捗を記録しているため、次回実行時は続きから再開されます。

```bash
systemctl --user stop xsaved-process
systemctl --user start xsaved-process   # すぐに続きの計算を開始する場合
```

## バックアップ

`xsaved-backup` が毎日、取得済みツイート（`tweets/`）とデータベース全体のダンプ（`backup/xsaved.sql`）を Google Drive 上の restic リポジトリ（`gdrive:xsaved-backup`）へ同期します。
X 上で削除されたツイートは再取得できないため、このバックアップと保存先のサブボリュームのみが唯一のデータ退避先となります。
保持世代は日次 7、週次 4、月次 12 となっており、それより古い世代はバックアップのたびに削除されます。

リポジトリは restic により暗号化されています。パスワードは `secrets/secrets.yaml` 内の `xsaved_restic_password` に格納されており、switch 実行時に `~/.config/xsaved/restic-password` へ配置されます。
復号に使用する age 鍵は Bitwarden にも保管されているため、本マシンが故障した場合でも別マシンで secrets を復号すればパスワードを復元できます。

バックアップの世代一覧を確認するコマンド：

```bash
export RESTIC_REPOSITORY=rclone:gdrive:xsaved-backup RESTIC_PASSWORD_FILE=~/.config/xsaved/restic-password
nix shell nixpkgs#restic -c restic snapshots
```

保存先のサブボリュームだけが破損した場合、データベース（NVMe 上）は無事なためファイルのみを復元します。

```bash
systemctl --user stop xsaved-sync.timer xsaved-process.timer
nix shell nixpkgs#restic -c restic restore latest --target / --include ~/.local/share/xsaved/tweets
systemctl --user start xsaved-sync.timer xsaved-process.timer
```

新しいマシンへの移行時などデータベースも含めて消失した場合は、ファイルを復元した後にダンプデータを空のデータベースへ流し込みます。
定期実行の `xsaved migrate` が先に空のテーブルを作成してしまうとダンプの投入時に衝突するため、タイマーを停止してから既存テーブルを削除して復元を行ってください。
`DROP OWNED BY` は実行ユーザーが所有するテーブルのみを削除し、NixOS 側で作成された拡張（extension）は残します。

```bash
systemctl --user stop xsaved-sync.timer xsaved-process.timer
nix shell nixpkgs#restic -c restic restore latest --target /
psql -h /run/postgresql -d xsaved -c 'DROP OWNED BY CURRENT_USER'
psql -h /run/postgresql -d xsaved -f ~/.local/share/xsaved/backup/xsaved.sql
systemctl --user start xsaved-sync.timer xsaved-process.timer
```

リストア時に拡張機能へのコメント記述（`COMMENT ON EXTENSION`）の 2 行で `must be owner of extension` というエラーが出ますが、データの整合性には影響しません。
ダンプには OCR テキストや埋め込みベクトルも含まれているため、リストア後に再計算する必要はありません。
uv の実行環境およびモデルファイルはバックアップ対象外のため、初回 `xsaved` 実行時に自動で再取得されます。

## 環境内での挙動の変化

ライブラリ、PATH、`/etc`、`sudo` の扱いについては [uv-mode](./cli-tools/uv-mode.md#モード内での変化点) と同様です。
設定される環境変数やデータディレクトリ内の配置については [xsaved-env](../../packages/xsaved-env/default.nix) を参照してください。

## トラブルシューティング

`@xsaved` がマウントされていない場合、処理を実行せずに以下のエラーで停止します。

```text
xsaved-env: /home/pomu/.local/share/xsaved がマウントされていません。手順: docs/howtouse/xsaved.md
```

`findmnt /home/pomu/.local/share/xsaved` でマウント状態を確認し、サブボリューム自体が存在しない場合は「初回準備」の手順を実行してください。
サブボリュームは存在するもののマウントされていない場合は、前述の `systemctl start` コマンドでマウントを実行します。

`XSAVED_X_USER is not set` で停止した場合は、`x-user` ファイルを作成してアカウント名を記述してください。

データベースに接続できない場合は、`systemctl status postgresql postgresql-setup` で PostgreSQL 本体および DB・拡張機能の生成処理のステータスを確認してください。

`xsaved embed` 実行時に `waiting for the GPU lock /run/xsaved-gpu.lock` と表示されて停止している場合は、他の `xsaved embed` プロセス（夜間の `xsaved-process` や他ユーザーの実行）の完了を待機しています。
`systemctl --user status xsaved-process` で夜間処理などがバックグラウンドで動作していないか確認してください。
