# X のいいねの保存と意味検索

X でいいねしたツイートを、本文、画像、動画、引用元ごと手元に保存し、文章で検索したり似たツイートを探したりする。
ツール本体は x-likes-archive（`~/sagyo/x-likes-archive`、リモートなし）で、コマンドの一覧はその README、設計はその `docs/design.md` にある。
この文書は、このリポジトリが nixos-desktop に用意する実行環境、データベース、定期実行の使い方を扱う。

設定は [home-manager-pomu.nix](../../hosts/nixos-desktop/home-manager-pomu.nix) の `local.xLikes` で有効にし、[x-likes.nix](../../modules/home-manager/x-likes.nix) がコマンドと定期実行を、[modules/nixos/x-likes.nix](../../modules/nixos/x-likes.nix) が Postgres のデータベースを用意する。
設計判断は [architecture/x-likes.md](../architecture/x-likes.md)。

## 初回の準備

データは SATA SSD の subvol `@x-likes` に置く。
subvol は自動では作られないので、[disk-tiering.md の「新しい subvol を足す」](./disk-tiering.md#新しい-subvol-を足す)の手順で一度だけ作る。
`@x-likes` に固有のコマンドは次のとおり。

```sh
sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
sudo nix shell nixpkgs#btrfs-progs -c btrfs subvolume create /mnt/sda/@x-likes
sudo chown pomu:users /mnt/sda/@x-likes
sudo umount /mnt/sda
sudo nixos-rebuild switch --flake .#nixos-desktop
```

マウント定義には `nofail` が付いているので、subvol を作る前に switch や再起動をしても起動は止まらない。
その場合は、subvol を作ってから再起動するか、次のコマンドでマウントする。

```sh
sudo systemctl start home-pomu-.local-share-x-likes.mount
```

いいね欄を取得する X のアカウント名（`@` を除いたもの）を、データディレクトリの `x-user` に書く。
このリポジトリは公開しているので、アカウント名は Nix の設定に書かない。

```sh
echo <アカウント名> > ~/.local/share/x-likes/x-user
```

いいね欄は Firefox のログイン状態（cookie）で取得するので、Firefox で X にログインしておく。

最初の `xlikes` の実行で、uv が Python、ROCm 版の torch などをデータディレクトリに取得する（数 GB）。
最初の `xlikes sync` は、取得済みのファイルがないので、いいね欄を最後まで辿る。

## 使い方

```bash
xlikes search '鶏肉の焼き方'
xlikes similar <ツイートID>
xlikes status
xlikes delete <ツイートID>
xlikes fetch likejs <公式アーカイブの like.js>
```

`xlikes` は x-likes-archive の CLI を `x-likes-env` の中で実行する。
引数は x-likes-archive の README のコマンドと同じで、`python -m xlikes` の部分を `xlikes` に置き換える。
`x-likes-env` を引数なしで実行すると環境のシェルに入り、引数を付けるとそのコマンドだけを環境の中で実行する。

`xlikes` は `~/sagyo/x-likes-archive` で今チェックアウトしている版を、その `uv.lock` のとおりに実行する。
ブランチを切り替えると、手で実行するコマンドも定期実行も、切り替えた先の版が実行される。

## 定期実行

二つの systemd user timer を設定している。

| timer | 時刻 | 実行する内容 |
|-------|------|-------------|
| `xlikes-sync` | 毎時 0 分 | `xlikes sync`（いいね欄と引用元の取得と登録） |
| `xlikes-process` | 毎日 4:00 | `xlikes embed text`、`ocr`、`embed images`、`embed text` の順 |

どちらも始めに `xlikes migrate` を実行するので、x-likes-archive を更新してスキーマが変わっても、次の実行で適用される。
`xlikes-process` は途中の手順が失敗しても残りの手順を進め、最後に失敗として終わる。
どちらの timer も、失敗すると GNOME に通知が出る（[failure-notify.md](./failure-notify.md)）。
電源が切れていて 4:00 を逃すと、次の起動時に実行される。
nixos-desktop の pomu は linger にしてあるので、どちらの timer もログインしていなくても動く。linger でないユーザーでは、ログインしている間だけ動き、逃した分は次のログイン時に実行される。

```bash
systemctl --user list-timers 'xlikes-*'
journalctl --user -u xlikes-sync -u xlikes-process
xlikes status
```

`xlikes-process` は、取り込んだ件数が多いと何時間も続く。
GPU を使うアプリと重なったら止めてよい。
OCR と埋め込みは一件ずつ記録するので、次の実行は続きから始まる。

```bash
systemctl --user stop xlikes-process
systemctl --user start xlikes-process   # すぐに続きを計算する
```

## 環境の中で変わること

ライブラリ、PATH、`/etc`、`sudo` の扱いは [uv-mode](./cli-tools/uv-mode.md#モードの中で変わること) と同じで、`/usr/lib` に見えるライブラリは [mimikopi-env](./cli-tools/mimikopi-env.md#環境の中で変わること) と同じものから `ffmpeg` を除いたもの。

次の環境変数が設定される。データディレクトリは `~/.local/share/x-likes`（`@x-likes` のマウント先）。

| 変数 | 値 | 用途 |
|------|----|------|
| `UV_PYTHON_PREFERENCE` | `only-managed` | uv に Nix の `python3` を選ばせない |
| `UV_CACHE_DIR` | `<データディレクトリ>/uv-cache` | uv のキャッシュ |
| `UV_PYTHON_INSTALL_DIR` | `<データディレクトリ>/python` | uv が取得する Python |
| `UV_PROJECT_ENVIRONMENT` | `<データディレクトリ>/venv` | x-likes-archive の Python 環境 |
| `HF_HOME` | `<データディレクトリ>/huggingface` | 埋め込みモデルのチェックポイント |
| `XLIKES_DATA_DIR` | `<データディレクトリ>/tweets` | 取得したメタデータ、メディア、gallery-dl の取得済みの記録 |
| `XLIKES_DATABASE_URL` | `host=/run/postgresql dbname=xlikes` | Postgres のデータベース |
| `XLIKES_GALLERY_DL` | Nix の gallery-dl | いいね欄の取得に使う gallery-dl |
| `XLIKES_X_USER` | `<データディレクトリ>/x-user` の中身 | いいね欄を取得するアカウント。外で設定済みならそちらを使う |
| `HSA_OVERRIDE_GFX_VERSION` | `10.3.0` | ROCm に GPU を gfx1030 として扱わせる |

## うまく動かないとき

`@x-likes` がマウントされていないと、何も実行せずに次のエラーで止まる。

```text
x-likes-env: /home/pomu/.local/share/x-likes がマウントされていません。手順: docs/howtouse/x-likes.md
```

`findmnt /home/pomu/.local/share/x-likes` で状態を確かめ、subvol が無ければ「初回の準備」を行う。
subvol があるのにマウントされていなければ、上の `systemctl start` でマウントする。

`XLIKES_X_USER is not set` で止まったら、`x-user` を書く。

データベースに接続できなければ、`systemctl status postgresql postgresql-setup` で Postgres と、データベースと拡張を作る処理の状態を確かめる。
