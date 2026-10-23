# X のいいねの保存と意味検索の実行環境

[howtouse/x-likes.md](../howtouse/x-likes.md) の設計判断。
ツール本体（取得、登録、OCR、埋め込み、検索）の設計は x-likes-archive の `docs/design.md` にあり、ここでは nixos-desktop で動かすための環境、データベース、定期実行を扱う。

## 使いみち

x-likes-archive は、gallery-dl で X のいいね欄と引用元を取得し、Postgres（pgvector と PGroonga）に登録し、ruri-v3-310m と Qwen3-VL-Embedding-2B の埋め込みと RapidOCR の文字で検索する。
埋め込みは RX 6600 の GPU で計算するので、[mimikopi-env](./mimikopi-env.md) と同じく、uv が取得する Python に ROCm 版の torch を入れて FHS 環境で動かす。
Postgres には拡張が二つ要る。いいね欄の取得と、OCR と埋め込みの計算は、定期的に実行する。

## 確かめた結果

2026-10-21 に nixos-desktop で確かめた。

- Postgres 17.11、pgvector 0.8.2、PGroonga 4.0.5（nixpkgs 26.05、4feb8eb）で、superuser が拡張を作ったデータベースを一般ロールに所有させると、そのロールで x-likes-archive の migrate、PGroonga の全文検索、pgvector の距離計算が通った。
- 二つの拡張の control ファイルには `trusted = true` がないので、superuser でないロールは `CREATE EXTENSION` を実行できない。
- `x-likes-env` を `systemd-run --user` の中で起動すると、bwrap の FHS 環境が立ち上がり、データディレクトリがマウントされていなければマウント確認で止まった。
- 取得から検索までの処理は、switch 前に `mimikopi-env` の中で、一時的な Postgres を使って実データで確かめてある。

## FHS 環境を mimikopi-env と分ける

[packages/x-likes-env](../../packages/x-likes-env/default.nix) は mimikopi-env と同じ形の buildFHSEnv で、ROCm 版の torch が読むライブラリを持つ。
mimikopi-env を、名前とデータディレクトリを引数で受け取る汎用の環境に作り替えれば定義は一つで済むが、耳コピの環境にも手が入る。
用途が二つのうちは別の環境にし、三つ目が出てきたときにまとめるかを決める。

代わりに、同じ版の torch を二つの subvol に一つずつ持つ。
btrfs は subvol をまたぐハードリンクを作れないので、uv のキャッシュを共有しても環境へはコピーになる。
mimikopi-env で測ったときは、ROCm 版の torch の環境は展開後に約 15GB、`compress=zstd` でディスク上は約 5GB だった。

## データを SATA の専用 subvol に置く

SATA SSD に `@x-likes` を作り、`~/.local/share/x-likes` にマウントする（[data-disk.nix](../../hosts/nixos-desktop/data-disk.nix)）。
取得したメディアと、uv の環境とモデルのチェックポイントはどれも大きく、読み書きはシーケンシャルが中心なので、[disk-tiering.md](./disk-tiering.md) の分け方ではコールド層に当たる。

取得したツイート（`tweets/`）と、取得し直せる環境（`venv/`、`uv-cache/`、`python/`、`huggingface/`）を一つの subvol に置く。
subvol を分ければスナップショットやバックアップの単位を分けられるが、手で作る subvol が増える。
バックアップを作るときは `tweets/` だけを対象にする。

マウントの扱いは `@mimikopi` と同じで、作る前の switch や再起動で起動を止めないよう `nofail` を付け、`x-likes-env` が起動時に `mountpoint -q` で確かめて、マウントされていなければ止まる。
[tests/default.nix](../../tests/default.nix) は `nofail` が付いていることを確かめる。

## Postgres を OS のサービスで動かす

[modules/nixos/x-likes.nix](../../modules/nixos/x-likes.nix) が、Home Manager で `local.xLikes` を有効にしたユーザーごとに、NixOS の `services.postgresql` でデータベースを作る。
データベースの名前は Home Manager 側の `local.xLikes.database` が正本で、NixOS 側はそれを読む。データディレクトリを Home Manager 側で決めて OS のマウントがそれを読むのと同じ向きにした。
名前は、NixOS 側が superuser として実行する SQL と、xlikes の接続文字列に埋め込むので、英小文字、数字、`_` だけの 63 バイトまでに限る（先頭は数字以外）。
[tests/default.nix](../../tests/default.nix) は、Home Manager 側の名前のデータベースを Postgres が作ることを確かめる。

データベースはそのユーザーが所有し、Unix socket の peer 認証で接続する。パスワードは使わない。
nixpkgs の `ensureDBOwnership` はユーザーと同じ名前のデータベースにしか使えないので、所有者は `postgresql-setup` の最後に `ALTER DATABASE` で付ける。
拡張は所有者には作れないので、同じ所で superuser として作る。x-likes-archive の migrate の `CREATE EXTENSION IF NOT EXISTS` は、作成済みなら何もしない。

Postgres のメジャー版は 17 に固定する。既定値は `system.stateVersion` で決まり、メジャー版が変わるとデータディレクトリの移行が要るからである。

データディレクトリは既定の `/var/lib/postgresql/17`（NVMe）のままにする。
データベースに入るのは本文、メタデータ、OCR の文字、ベクトル（ツイート 1 件あたり ruri が 3KB と Qwen が 8KB、画像 1 枚あたり 8KB）で、メディアは入らない。
検索はランダム読みになるので、disk-tiering.md の分け方ではホット層に当たる。

## アカウント名をリポジトリに書かない

いいね欄を取得する X のアカウント名は、データディレクトリの `x-user` から `x-likes-env` が読む。
このリポジトリは公開しているので、Nix の設定に書くと GitHub のアカウントと X のアカウントが結び付く。

## checkout をそのまま実行する

`xlikes` は `local.xLikes.projectDir` の checkout を `uv run --project ... --frozen` で実行する。
ML の依存（ROCm 版の torch の wheel など）は x-likes-archive の `uv.lock` で決まっていて、Nix のパッケージにすると uv の lock と二重に管理することになる。
代わりに、checkout のブランチを切り替えると、定期実行もその版が実行される。

スキーマの変更を取り込み忘れないよう、二つのサービスはどちらも始めに `xlikes migrate` を実行する。
二つが同時に始まっても同じ SQL を二度流さないよう、x-likes-archive の migrate は Postgres の advisory lock を取る。

## 定期実行

[x-likes.nix](../../modules/home-manager/x-likes.nix) が二つの systemd user timer を定義する。

`xlikes-sync` は毎時、いいね欄と引用元を取得して登録する。
gallery-dl は取得済みのファイルが 20 件続いたら止まるので、普段の実行は数秒から十数秒で終わる。
初回は取得済みのファイルがないので、いいね欄を最後まで辿る。前の実行が終わるまで、timer は次の実行を始めない。

`xlikes-process` は毎日 4:00 に、本文の埋め込み、OCR、画像の埋め込み、本文の埋め込みの順で計算する。
GPU を使う計算を、ゲームなどと重なりにくい時刻に寄せる。
本文の埋め込みは数分で終わるので先に済ませ、取り込んだ直後から意味検索できるようにする。
OCR の文字は ruri の入力に入るので、最後にもう一度本文を埋め込む。入力が変わったツイートだけが計算される。
OCR は CPU の全コアを使うので、`Nice=19` と `IOSchedulingClass=idle` で前面のアプリに譲る。
`Persistent=true` なので、電源が切れていて逃した分は、ユーザーのサービスマネージャーが次に起動したときに実行される。
nixos-desktop では pomu を linger にしているので、ログインを待たずに OS の起動時に実行される（[tailscale.md](./tailscale.md#ログインしていなくてもユーザーの-timer-を動かす)）。

## 退けた案

- mimikopi-env を汎用化して両方から使う。上の「FHS 環境を mimikopi-env と分ける」に書いた理由で、今は退けた。
- x-likes-archive を Nix のパッケージや flake input にする。上の「checkout をそのまま実行する」に書いた理由で退けた。
- Postgres のデータディレクトリを `@x-likes` に置く。`@x-likes` は `nofail` でマウントするので、マウントされていないときにルート側へ初期化させない仕組みが別に要る。データベースは NVMe に置ける大きさなので退けた。
- Postgres をユーザーの systemd サービスで動かす。データディレクトリをユーザーが持てるが、起動、拡張の読み込み、更新を自分で書くことになる。NixOS のモジュールで足りるので退けた。

## 代償

`xlikes` と、x-likes-archive の環境の Python を使うものは、`x-likes-env` の中で実行する必要がある。
`@x-likes` がマウントされていない間は、`x-likes-env` は何も実行せずに止まり、定期実行は失敗として記録される。
ROCm 版の torch を、耳コピの環境と別に持つ。

## 未確定

- バックアップ。`tweets/` と Postgres のどちらを、どこへ、どう暗号化して置くかは、x-likes-archive の設計でも決まっていない。Postgres の中身は、最初に見つけた日時（`first_seen_at`）を除いて `tweets/` から作り直せる。
- いいねが増えたときのデータベースの大きさ。ベクトルの索引（HNSW）を作るかどうかと合わせて、実データで決める。
