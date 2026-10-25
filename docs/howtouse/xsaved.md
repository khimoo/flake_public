# X のいいね・ブックマークの保存と意味検索

X で「いいね」またはブックマークしたツイートを、本文・画像・動画・引用元を含めてローカルに保存し、自然言語検索や類似ツイートの検索を行えるようにします。
ツール本体には、プライベートリポジトリ [khimoo/xsaved](https://github.com/khimoo/xsaved) の本番用チェックアウト（`~/.local/share/xsaved-app`）を使用します。開発用チェックアウトは `~/sagyo/xsaved` に配置します。コマンド一覧はリポジトリ本体の README を参照してください。
nixos-desktop の pomu 環境では、開発用チェックアウトのみが `clone-repos` の対象です。本番用チェックアウトの作成・更新手順は「[本番用チェックアウトの更新](#本番用チェックアウトの更新)」を、新規環境のセットアップ手順は [SSH 鍵の配布と private repo の clone](private-repo-clone.md) を、保存済みツイートとデータベースの復元方法は「[バックアップ](#バックアップ)」をそれぞれ参照してください。

設定箇所は [home-manager-pomu.nix](../../hosts/nixos-desktop/home-manager-pomu.nix) の `local.xsaved` です。

設計ドキュメント: [X のいいねとブックマークの保存の設計](../architecture/xsaved.md)

## 初回準備

データは SATA SSD のサブボリューム `@xsaved` に保存します。
サブボリュームは自動作成されないため、[disk-tiering.md の「新しい subvol の追加手順」](./disk-tiering.md#新しい-subvol-の追加手順) に従って事前に作成してください。
`@xsaved` 固有の作成手順は以下のとおりです。

```sh
sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
sudo nix shell nixpkgs#btrfs-progs -c btrfs subvolume create /mnt/sda/@xsaved
sudo chown pomu:users /mnt/sda/@xsaved
sudo umount /mnt/sda
sudo nixos-rebuild switch --flake .#nixos-desktop
```

マウント設定に `nofail` オプションを指定しているため、サブボリューム作成前に switch や再起動を行っても、システムの起動が妨げられることはありません。
作成前に switch や再起動を行った場合は、サブボリューム作成後に再起動するか、以下のコマンドで手動マウントしてください。

```sh
sudo systemctl start home-pomu-.local-share-xsaved.mount
```

いいねを取得したい X のアカウント名（`@` を除いた文字列）を、データディレクトリ内の `x-user` ファイルに書き込みます。
このリポジトリは公開されているため、アカウント名は Nix の設定ファイルに直接記述しないでください。

```sh
echo <アカウント名> > ~/.local/share/xsaved/x-user
```

いいねとブックマークの取得には Firefox のログイン情報（Cookie）を利用するため、あらかじめ Firefox で X にログインしておいてください。ブックマークはログイン中のアカウントから取得されます。

最初に `xsaved` を実行した際、uv が Python 本体と依存パッケージをデータディレクトリへダウンロードします。また、`ocr`、`embed`、`tag`、`search`、`serve` を初めて実行する際には、ROCm 版 PyTorch など（数 GB 程度）もダウンロードされます。
初回 `xsaved sync` 実行時はローカルにデータが存在しないため、いいね欄とブックマーク欄から、X の一覧で取得可能な最も古いデータまで遡って取得します。
なお、ブックマークは公式アーカイブに含まれないため、一覧に表示されない過去のデータは取得できません（本体の `TODO.md` を参照）。

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

`search` と `similar` は、デフォルトでいいねとブックマークの両方を検索対象とします。`--source likes` または `--source bookmarks` を指定することで、どちらか一方に絞り込んで検索することも可能です。
`xsaved delete` は、対象ツイートがいいね・ブックマークのどちらであるかを問わず、ローカルに保存されたデータを完全に削除します。なお、X 上でいいねやブックマークを解除しても、ローカルに保存されたデータは自動削除されず保持されます。
`xsaved retry` は、取得に失敗した返信先や引用元、like.js のいいね、および欠落している画像や動画を再取得します。定期実行には含まれないため、`xsaved status` の `incomplete_media`（メディアが欠けているツイート数）が増加した際などに手動で実行してください。

引数は xsaved の README に記載されているコマンドと同様で、`python -m xsaved` を `xsaved` に置き換えて実行できます。
`xsaved-env` を引数なしで実行すると専用環境のシェルが起動し、引数を指定した場合はそのコマンドのみを環境内で実行します。

`xsaved` や定期実行処理は、本番用チェックアウト（`~/.local/share/xsaved-app`）のバージョンで動作します。開発用チェックアウト（`~/sagyo/xsaved`）を編集しても、そのままでは定期実行には反映されません。

### 本番用チェックアウトの更新

本番用チェックアウトは開発用チェックアウトから clone したものであり、開発用チェックアウトの main ブランチの変更を取り込みます。
開発用チェックアウトの main にコミットした後、`xsaved-update` を実行してください。

```bash
xsaved-update
```

`xsaved-update` は、定期実行タイマーと Web UI を停止し、実行中の取得や計算の完了を待ってバックアップを取得してから、本番用チェックアウトで `git pull --ff-only` を実行します。その後、取り込んだコミットを表示して `xsaved migrate` を実行し、最後にタイマーと Web UI を再開します（処理の途中で失敗した場合も再開されます）。

新しいマシン環境では、`clone-repos` で開発用チェックアウトを用意した後に本番用チェックアウトを作成します。

```bash
git clone ~/sagyo/xsaved ~/.local/share/xsaved-app
```

## Web UI

nixos-desktop 上のブラウザで <http://xsaved.localhost/> を開くと、検索および類似ツイート検索を利用できます。
「検索対象」で「すべて」「いいね」「ブックマーク」を選択でき、この選択は「似たツイート」や「もっと表示」の検索条件にも引き継がれます。
検索を実行すると、ruri（本文＋OCRテキスト）、Qwen（本文＋OCRテキスト）、Qwen（画像と動画）、全文検索、PixAI タグの結果が、それぞれ独立した列に並んで表示されます。全文検索では、スペース区切りで AND 検索、`OR` 区切りで OR 検索が可能です。全文検索は投稿者の ID（`@` 付き）と表示名も対象にします。
Qwen（画像と動画）の列では、動画から取り出したフレームも画像と同じように比べ、動画は最も似ているフレームの順位で並びます。
PixAI タグの列は、画像と動画のフレームに付いた作品とキャラクターのタグ（英語の Danbooru 名と、日本語名などの別名）で探します。「ブルアカ ホシノ」のようにスペースで区切ると、すべての語に当たるタグを持つ画像や動画のツイートを出します。動画は、そのタグが付いたフレームの割合が高いほど上に並びます。
いずれの列でも、引用元の本文や画像がヒットした場合は、それを引用している保存ツイートが表示されます。本文の列では保存ツイートと引用元を個別に比較しますが、全文検索では双方のテキストを結合して検索するため、検索ワードが別々のツイートに分かれて含まれていてもヒットします。
検索結果の各ツイートにある「似たツイート」ボタンを押すと、そのツイートに類似した保存ツイートを、全文検索と PixAI タグを除く 3 つの列で横断検索します。
各列は個別にスクロール可能で、「もっと表示」をクリックすると続きを 20 件ずつ追加で読み込めます。古い検索結果の続きを取得できなくなった場合は、再度検索を実行してください。

サーバーは常駐しません。アクセス時に systemd ソケット経由でオンデマンド起動し、15 分間リクエストがないと自動で停止します。
サーバー起動後の初回検索時は GPU に埋め込みモデルをロードするため、1 分以上の時間がかかります。一度ロードされれば、サーバー停止までは 2 秒前後でレスポンスが返ります。
夜間に `xsaved-process` が埋め込み計算を行っている間と、`xsaved-frames` が動画のフレームを計算している間は、モデルを利用する 3 列に「GPU を使うほかの計算（夜間の埋め込みなど）が終わるまで、モデルを使う検索はできません。」と表示されます。ただし、その間も全文検索と PixAI タグの列、および類似ツイート検索は利用可能です。
逆に、検索サーバーの稼働中に 4:00 を迎えた場合、`xsaved-process` は検索サーバーが停止するまで（最後のリクエストから最大 15 分間）埋め込み計算の開始を待機します。
サーバー停止時には、モデルが占有していた VRAM も自動的に解放されます。

```bash
systemctl --user status xsaved-web.socket xsaved-web-server
journalctl --user -u xsaved-web-server
systemctl status caddy
journalctl -u caddy
```

アクセスはローカルマシンからのみ可能です。URL には `http://` を指定してください。
Caddy が動作していない場合は、<http://127.0.0.1:8765/> へ直接接続することで問題の切り分けが可能です。
内部接続先のポートは `local.xsaved.webPort` で変更でき、Caddy の転送先も自動追従します。サーバー本体はその次のポート番号で待機します。

## 定期実行

以下の systemd ユーザータイマーを設定しています。なお、`xsaved-backup` は `local.xsaved.backup.repository` が設定されている場合のみ有効になります。

| タイマー | 実行時刻 | 実行内容 |
|-------|------|-------------|
| `xsaved-sync` | 毎時 0 分 | `xsaved sync`（いいね・ブックマーク欄、返信先や引用元の取得と登録） |
| `xsaved-process` | 毎日 4:00 | `xsaved embed text` → `ocr` → `embed images` → `tag` → `tag-names` → `embed text` の順で実行 |
| `xsaved-backup` | 毎日 6:00 | 取得ツイートとデータベースを restic で同期（後述の「バックアップ」参照） |

`xsaved-process` は、始めに `xsaved-frames` を止め、終わると起動し直します。
`xsaved-frames` は、動画から取り出したフレームを 8 秒、4 秒、2 秒、1 秒ごとの順に埋め込み、タグを付け、すべて終えると止まります。
新しい動画は、古い動画の細かい間隔より先に計算されます。
初回は全動画を計算するので、止めなければ数日かかります。
`xsaved status` の `frames_without_qwen` と `frames_without_tags` が、残りのフレームの数です。

`xsaved-sync` と `xsaved-process` は、起動時に毎回 `xsaved migrate` を実行するため、xsaved 本体の更新によってデータベーススキーマが変更されても次回実行時に自動で適用されます。
`xsaved-process` は途中のステップで失敗しても残りの処理を継続し、最終的な終了コードとして失敗ステータスを返します。
いずれかのタイマーが失敗した場合は、GNOME 上にエラー通知が表示されます（[failure-notify.md](./failure-notify.md)）。
電源オフなどで 4:00 や 6:00 の実行タイミングを逃した場合は、次回のシステム起動時に自動実行されます。
nixos-desktop の pomu ユーザーは linger を有効化しているため、ログインしていなくてもすべてのタイマーが動作します。linger が無効なユーザーの場合はログイン中のみ動作し、未実行分は次回ログイン時にまとめて処理されます。

```bash
systemctl --user list-timers 'xsaved-*'
journalctl --user -u xsaved-sync -u xsaved-process -u xsaved-frames
xsaved status
```

新規取り込み件数が多い場合、`xsaved-process` の完了までに数時間かかることがあります。
GPU を使用する他のアプリケーションと競合した場合は、途中で停止しても問題ありません。
OCR や埋め込み計算は 1 件ごとに進捗が記録されるため、次回実行時は中断した箇所から再開されます。

```bash
systemctl --user stop xsaved-process
systemctl --user start xsaved-process   # すぐに続きの計算を開始する場合
```

ゲームなどで GPU を使うときは、`xsaved-frames` を止めます。計算したフレームは残り、翌晩の `xsaved-process` のあとに続きから再開します。

```bash
systemctl --user stop xsaved-frames
systemctl --user start xsaved-frames    # すぐに再開する場合
```

## バックアップ

`xsaved-backup` により、取得済みツイート（`tweets/`）、データベース全体のダンプ（`backup/xsaved.sql`）、埋め込みモデル（`huggingface/hub`）、バックアップ時の flake_public と xsaved のコミット記録（`backup/revisions`）が、毎日 Google Drive 上の restic リポジトリ（`gdrive:xsaved-backup`）へ同期されます。
バックアップは、書き込みを伴う `xsaved` の処理（定期実行・手動実行）の完了を待ってから開始されます。また、バックアップの実行中に開始された処理は、バックアップが完了するまで待機します。
X 上で削除されたツイートは再取得できないため、このバックアップと保存先サブボリュームが唯一のデータ退避先となります。
保持世代は日次 7 世代、週次 4 世代、月次 12 世代で、これらを超えた古い世代はバックアップ実行時に自動削除されます。

リポジトリは restic によって暗号化されています。パスワードは `secrets/secrets.yaml` 内の `xsaved_restic_password` に格納されており、switch 実行時に `~/.config/xsaved/restic-password` へ配置されます。
復号用の age 鍵は Bitwarden にも保管されているため、本マシンが故障した場合でも、別マシンで secrets を復号すればパスワードを復元できます。

最新のバックアップから正常に復元できるかどうかは、`xsaved-restore-check` で確認できます。
本番のデータやデータベースには影響を与えず、ダンプを一時的な PostgreSQL インスタンスに読み込んで件数や検索を検証します。あわせて、メディアファイルがすべてバックアップ内に存在することと、ランダムに選んだ 20 件のハッシュ値がデータベースと一致するかを確認します。
問題がなければ終了コード 0 で正常終了します。

```bash
xsaved-restore-check
```

バックアップの世代一覧を確認するコマンド:

```bash
export RESTIC_REPOSITORY=rclone:gdrive:xsaved-backup RESTIC_PASSWORD_FILE=~/.config/xsaved/restic-password
nix shell nixpkgs#restic -c restic snapshots
```

保存先サブボリュームのみが破損した場合、データベース（NVMe 上）は影響を受けないため、ファイル群のみをリストアします。

```bash
systemctl --user stop xsaved-sync.timer xsaved-process.timer xsaved-sync xsaved-process xsaved-frames
nix shell nixpkgs#restic -c restic restore latest --target / --include ~/.local/share/xsaved/tweets
systemctl --user start xsaved-sync.timer xsaved-process.timer
```

新マシンへの移行などでデータベースも含めて消失した場合は、ファイルを復元した後に空のデータベースへダンプデータを投入します。
定期実行の `xsaved migrate` が先に空テーブルを作成してしまうと、ダンプ投入時に競合してしまいます。そのため、タイマーと実行中の処理を停止したうえで既存テーブルを削除してからリストアを行ってください。手動での `xsaved` 実行も控えてください。
`DROP OWNED BY` は実行ユーザーが所有するテーブルのみを削除し、NixOS 側で作成された拡張機能（extension）はそのまま保持します。

```bash
systemctl --user stop xsaved-sync.timer xsaved-process.timer xsaved-backup.timer xsaved-web.socket xsaved-sync xsaved-process xsaved-frames xsaved-backup xsaved-web-server
nix shell nixpkgs#restic -c restic restore latest --target /
psql -h /run/postgresql -d xsaved -c 'DROP OWNED BY CURRENT_USER'
psql -h /run/postgresql -d xsaved -f ~/.local/share/xsaved/backup/xsaved.sql
systemctl --user start xsaved-sync.timer xsaved-process.timer xsaved-backup.timer xsaved-web.socket
```

リストア時に拡張機能へのコメント付与（`COMMENT ON EXTENSION`）に関する 2 行で `must be owner of extension` というエラーが出力されますが、データの整合性には影響ありません。
ダンプデータには OCR テキストや埋め込みベクトルも含まれているため、リストア後に再計算を行う必要はありません。
埋め込みモデルもバックアップから復元されます。uv の実行環境はバックアップ対象外ですが、初回 `xsaved` 実行時に自動で再取得されます。

## 環境内での挙動の変化

ライブラリ、PATH、`/etc`、`sudo` の扱いについては [uv-mode](./cli-tools/uv-mode.md#モード内での変化点) と同様です。
設定される環境変数やデータディレクトリ内の配置については [xsaved-env](../../packages/xsaved-env/default.nix) を参照してください。

## トラブルシューティング

`@xsaved` がマウントされていない場合、処理を実行せずに以下のエラーで停止します。

```text
xsaved-env: /home/pomu/.local/share/xsaved がマウントされていません。手順: docs/howtouse/xsaved.md
```

`findmnt /home/pomu/.local/share/xsaved` でマウント状態を確認し、サブボリューム自体が存在しない場合は「初回準備」の手順を実施してください。
サブボリュームは存在するもののマウントされていない場合は、前述の `systemctl start` コマンドでマウントを実行します。

`XSAVED_X_USER is not set` で停止した場合は、`x-user` ファイルを作成してアカウント名を記述してください。

データベースに接続できない場合は、`systemctl status postgresql postgresql-setup` で PostgreSQL 本体および DB・拡張機能のセットアップ状況を確認してください。

`xsaved embed` 実行時に `waiting for the GPU lock /run/xsaved-gpu.lock` と表示されて停止している場合は、他の `xsaved embed` プロセス（夜間の `xsaved-process` や他ユーザーの実行）の完了を待機しています。
`systemctl --user status xsaved-process xsaved-frames` で、夜間処理や動画のフレームの計算がバックグラウンドで動作していないか確認してください。
