# X のいいねの保存と意味検索

X で「いいね」したツイートを、本文・画像・動画・引用元ごとローカルに保存し、文章による検索や似たツイートの検索を行えるようにします。
ツール本体は x-likes-archive（`~/sagyo/x-likes-archive`、リモートなし）にあり、コマンド一覧はその README に記載されています。

設定箇所は [home-manager-pomu.nix](../../hosts/nixos-desktop/home-manager-pomu.nix) の `local.xLikes` です。

設計ドキュメント: [X のいいねの保存の設計](../architecture/x-likes.md)

## 初回準備

データは SATA SSD の subvol `@x-likes` に保存します。
subvol は自動作成されないため、[disk-tiering.md の「新しい subvol の追加手順」](./disk-tiering.md#新しい-subvol-の追加手順) の手順に従って一度だけ作成してください。
`@x-likes` 固有の実行手順は以下の通りです。

```sh
sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
sudo nix shell nixpkgs#btrfs-progs -c btrfs subvolume create /mnt/sda/@x-likes
sudo chown pomu:users /mnt/sda/@x-likes
sudo umount /mnt/sda
sudo nixos-rebuild switch --flake .#nixos-desktop
```

マウント設定に `nofail` オプションを指定しているため、subvol 作成前に switch や再起動を行ってもシステムの起動は阻害されません。
その場合は、subvol を作成後に再起動するか、以下のコマンドでマウントしてください。

```sh
sudo systemctl start home-pomu-.local-share-x-likes.mount
```

いいねを取得する X のアカウント名（`@` を除いた文字列）を、データディレクトリ内の `x-user` に書き込みます。
このリポジトリは公開設定になっているため、アカウント名は Nix の設定ファイルには記述しないでください。

```sh
echo <アカウント名> > ~/.local/share/x-likes/x-user
```

いいねのデータ取得には Firefox のログイン情報（cookie）を使用するため、あらかじめ Firefox で X にログインしておいてください。

最初に `xlikes` を実行した際、uv が Python や ROCm 版 PyTorch などをデータディレクトリへダウンロードします（数 GB 程度）。
最初の `xlikes sync` 実行時はデータが一切存在しないため、いいね欄を一番過去まで遡って取得します。

## 使い方

```bash
xlikes search '鶏肉の焼き方'
xlikes similar <ツイートID>
xlikes status
xlikes delete <ツイートID>
xlikes fetch likejs <公式アーカイブの like.js>
```

引数は x-likes-archive の README にあるコマンドと同様で、`python -m xlikes` を `xlikes` に置き換えて使用します。
`x-likes-env` を引数なしで実行すると専用環境のシェルに入り、引数を渡すとそのコマンドのみを環境内で実行します。

`xlikes` は `~/sagyo/x-likes-archive` で現在チェックアウトされているバージョンを実行します。ブランチを切り替えると、定期実行処理も切り替え先のバージョンで動作します。

## Web UI

nixos-desktop のブラウザで <http://xlikes.localhost/> を開くと、検索および類似ツイートの検索機能を利用できます。
検索を行うと、ruri（本文＋OCRテキスト）、Qwen（本文＋OCRテキスト）、Qwen（画像）、全文検索の結果がそれぞれ独立した列に並んで表示されます。全文検索ではスペース区切りで AND 検索、`OR` 区切りで OR 検索が可能です。
いずれの列でも、引用元の本文や画像がヒットした場合は、それを引用している「いいねしたツイート」を表示します。本文の列ではいいねしたツイートと引用元を個別に比較します。全文検索では両方のテキストを結合して探すため、検索語がそれぞれのツイートに分散していても検出できます。
検索結果のツイートにある「似たツイート」ボタンを押すと、そのツイートに類似したいいねを、全文検索を除く 3 つの列で検索します。

サーバーは常駐しません。アクセス時に systemd ソケット経由で起動し、15 分間リクエストがないと自動停止します。
サーバー起動後の初回検索では毎回埋め込みモデルを GPU に読み込むため、必ず 1 分以上かかります。読み込み完了後は、停止するまで 2 秒前後でレスポンスが返ります。
夜間に `xlikes-process` が埋め込み計算を行っている間は VRAM が不足するため、モデルを使用する 3 列には「検索に失敗しました」と表示されます。この間も全文検索の列と類似ツイート検索は利用可能です。
サーバーが停止すると、モデルが占有していた VRAM も解放されます。

```bash
systemctl --user status xlikes-web.socket xlikes-web-server
journalctl --user -u xlikes-web-server
systemctl status caddy
journalctl -u caddy
```

アクセスできるのは自マシンからのみです。URL は `http://` を指定してください。
Caddy が動いていない場合は <http://127.0.0.1:8765/> から直接接続して切り分けられます。
内部の接続先ポートは `local.xLikes.webPort` で変更できます。Caddy の転送先も追従し、サーバー本体はその次のポートで待機します。

## 定期実行

以下の systemd ユーザータイマーを設定しています。なお `xlikes-backup` は `local.xLikes.backup.repository` を設定した場合のみ有効化されます。

| タイマー | 実行時刻 | 実行内容 |
|-------|------|-------------|
| `xlikes-sync` | 毎時 0 分 | `xlikes sync`（いいね欄と引用元の取得・登録） |
| `xlikes-process` | 毎日 4:00 | `xlikes embed text` → `ocr` → `embed images` → `embed text` の順で実行 |
| `xlikes-backup` | 毎日 6:00 | 取得したツイートとデータベースを restic で同期（後述の「バックアップ」参照） |

`xlikes-sync` と `xlikes-process` は、実行開始時に `xlikes migrate` を行うため、x-likes-archive を更新してデータベーススキーマが変更された場合も次回実行時に自動適用されます。
`xlikes-process` は途中のステップで失敗しても残りの処理を継続し、最後に失敗ステータスで終了します。
各タイマーが失敗した場合は GNOME 上に通知が表示されます（[failure-notify.md](./failure-notify.md)）。
電源オフなどで 4:00 や 6:00 の実行を逃した場合は、次回のシステム起動時に実行されます。
nixos-desktop の pomu ユーザーは linger を有効化しているため、ログインしていなくても全タイマーが動作します。linger が無効なユーザーの場合はログイン中のみ動作し、逃した分は次回ログイン時に実行されます。

```bash
systemctl --user list-timers 'xlikes-*'
journalctl --user -u xlikes-sync -u xlikes-process
xlikes status
```

`xlikes-process` は新規取り込み件数が多いと完了まで数時間かかることがあります。
GPU を消費する他のアプリと競合した場合は途中で停止しても問題ありません。
OCR や埋め込み計算は 1 件ごとに進捗を記録しているため、次回実行時は続きから再開されます。

```bash
systemctl --user stop xlikes-process
systemctl --user start xlikes-process   # すぐに続きの計算を開始する場合
```

## バックアップ

`xlikes-backup` が毎日、取得済みツイート（`tweets/`）とデータベース全体のダンプ（`backup/xlikes.sql`）を Google Drive 上の restic リポジトリ（`gdrive:x-likes-backup`）へ同期します。
X 上で削除されたツイートは再取得できないため、このバックアップと保存先の subvol のみが唯一のデータ退避先となります。
保持世代は日次 7、週次 4、月次 12 とし、それより古い世代はバックアップのたびに削除されます。

リポジトリは restic により暗号化されています。パスワードは `secrets/secrets.yaml` 内の `x_likes_restic_password` に格納されており、switch 実行時に `~/.config/x-likes/restic-password` へ配置されます。
復号に使用する age 鍵は Bitwarden にも保管されているため、本マシンが故障した場合でも別マシンで secrets を復号すればパスワードを復元できます。

バックアップの世代一覧を確認するコマンド：

```bash
export RESTIC_REPOSITORY=rclone:gdrive:x-likes-backup RESTIC_PASSWORD_FILE=~/.config/x-likes/restic-password
nix shell nixpkgs#restic -c restic snapshots
```

保存先の subvol だけが破損した場合、データベース（NVMe 上）は無事なためファイルのみを復元します。

```bash
systemctl --user stop xlikes-sync.timer xlikes-process.timer
nix shell nixpkgs#restic -c restic restore latest --target / --include ~/.local/share/x-likes/tweets
systemctl --user start xlikes-sync.timer xlikes-process.timer
```

新しいマシンへの移行時などデータベースも含めて消失した場合は、ファイルを復元したあとにダンプデータを空のデータベースへ流し込みます。
定期実行の `xlikes migrate` が先に空のテーブルを作成してしまうとダンプの流し込み時に衝突するため、タイマーを停止してから既存テーブルを削除して復元を行ってください。
`DROP OWNED BY` は実行ユーザーが所有するテーブルのみを削除し、NixOS 側で作成された拡張（extension）は残します。

```bash
systemctl --user stop xlikes-sync.timer xlikes-process.timer
nix shell nixpkgs#restic -c restic restore latest --target /
psql -h /run/postgresql -d xlikes -c 'DROP OWNED BY CURRENT_USER'
psql -h /run/postgresql -d xlikes -f ~/.local/share/x-likes/backup/xlikes.sql
systemctl --user start xlikes-sync.timer xlikes-process.timer
```

リストア時に拡張機能へのコメント記述（`COMMENT ON EXTENSION`）の 2 行で `must be owner of extension` というエラーが出ますが、データ整合性には影響しません。
ダンプには OCR テキストや埋め込みベクトルも含まれているため、リストア後に再計算する必要はありません。
uv の実行環境およびモデルファイルはバックアップ対象外のため、初回 `xlikes` 実行時に自動で再取得されます。

## 環境内での挙動の変化

ライブラリ、PATH、`/etc`、`sudo` の扱いについては [uv-mode](./cli-tools/uv-mode.md#モード内での変化点) と同様です。
設定される環境変数やデータディレクトリ内の配置については [x-likes-env](../../packages/x-likes-env/default.nix) を参照してください。

## トラブルシューティング

`@x-likes` がマウントされていない場合、処理を実行せずに以下のエラーで停止します。

```text
x-likes-env: /home/pomu/.local/share/x-likes がマウントされていません。手順: docs/howtouse/x-likes.md
```

`findmnt /home/pomu/.local/share/x-likes` でマウント状態を確認し、subvol 自体が存在しない場合は「初回準備」の手順を実行してください。
subvol は存在するもののマウントされていない場合は、前述の `systemctl start` コマンドでマウントを実行します。

`XLIKES_X_USER is not set` で停止した場合は、`x-user` ファイルを作成してアカウント名を記述してください。

データベースに接続できない場合は、`systemctl status postgresql postgresql-setup` で PostgreSQL 本体および DB・拡張機能の生成処理のステータスを確認します。

`xlikes embed` 実行時に `waiting for the GPU lock /run/x-likes-gpu.lock` と表示されて停止している場合は、他の `xlikes embed` プロセス（夜間の `xlikes-process` や他ユーザーの実行）の完了を待機しています。
`systemctl --user status xlikes-process` で夜間処理などがバックグラウンドで動作していないか確認してください。
