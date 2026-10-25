# X のいいねとブックマークの保存の設計

使い方: [X のいいねとブックマークの保存と意味検索](../howtouse/xsaved.md)
実装: [xsaved.nix](../../modules/home-manager/xsaved.nix)（コマンドと定期実行）、[modules/nixos/xsaved.nix](../../modules/nixos/xsaved.nix)（データベース）、[xsaved-env](../../packages/xsaved-env/default.nix)

ツール本体（取得、登録、OCR、埋め込み、検索）の設計は xsaved の `docs/design.md` にあり、この文書は nixos-desktop で動かすための環境、データベース、定期実行を扱う。

## 使いみち

xsaved は、gallery-dl で X のいいね欄とブックマーク欄、返信先と引用元を取得し、Postgres（pgvector と PGroonga）に登録し、ruri-v3-310m と Qwen3-VL-Embedding-2B の埋め込みと RapidOCR の文字で検索する。
埋め込みは RX 6600 の GPU で計算するので、[mimikopi-env](./mimikopi-env.md) と同じく、uv が取得する Python に ROCm 版の torch を入れて FHS 環境で動かす。
Postgres には拡張が二つ要る。いいね欄とブックマーク欄の取得と、OCR と埋め込みの計算は、定期的に実行する。

## FHS 環境を mimikopi-env と分ける

[packages/xsaved-env](../../packages/xsaved-env/default.nix) は mimikopi-env と同じ形の buildFHSEnv で、ROCm 版の torch が読むライブラリを持つ。
mimikopi-env を、名前とデータディレクトリを引数で受け取る汎用の環境に作り替えれば定義は一つで済むが、耳コピの環境にも手が入る。
用途が二つのうちは別の環境にし、三つ目が出てきたときにまとめるかを決める。

代わりに、同じ版の torch を二つの subvol に一つずつ持つ。
btrfs は subvol をまたぐハードリンクを作れないので、uv のキャッシュを共有しても環境へはコピーになる。
mimikopi-env で測ったときは、ROCm 版の torch の環境は展開後に約 15GB、`compress=zstd` でディスク上は約 5GB だった。

## データを SATA の専用 subvol に置く

SATA SSD に `@xsaved` を作り、`~/.local/share/xsaved` にマウントする（[data-disk.nix](../../hosts/nixos-desktop/data-disk.nix)）。
取得したメディアと、uv の環境とモデルのチェックポイントはどれも大きく、読み書きはシーケンシャルが中心なので、[disk-tiering.md](./disk-tiering.md) の分け方ではコールド層に当たる。

取得したツイート（`tweets/`）と、取得し直せる環境（`venv/`、`uv-cache/`、`python/`、`huggingface/`）を一つの subvol に置く。
subvol を分ければスナップショットやバックアップの単位を分けられるが、手で作る subvol が増える。
バックアップを作るときは `tweets/` だけを対象にする。

マウントの扱いは `@mimikopi` と同じで、作る前の switch や再起動で起動を止めないよう `nofail` を付け、`xsaved-env` が起動時に `mountpoint -q` で確かめて、マウントされていなければ止まる。
この確認は、NixOS 側の `fileSystems` が `local.xsaved.dataDir` のマウントを定義しているときだけ入れる。
確認の目的は、nofail のマウントに失敗したときにルート側を埋めないことで、マウントを定義していないホストやユーザーには守るものがない。そうした構成では、データはホームの下にそのまま置かれる。
[tests/default.nix](../../tests/default.nix) は `nofail` が付いていることを確かめる。

## Postgres を OS のサービスで動かす

[modules/nixos/xsaved.nix](../../modules/nixos/xsaved.nix) が、Home Manager で `local.xsaved` を有効にしたユーザーごとに、NixOS の `services.postgresql` でデータベースを作る。
データベースの名前は Home Manager 側の `local.xsaved.database` が正本で、NixOS 側はそれを読む。データディレクトリを Home Manager 側で決めて OS のマウントがそれを読むのと同じ向きにした。
名前は、NixOS 側が superuser として実行する SQL と、xsaved の接続文字列に埋め込むので、英小文字、数字、`_` だけの 63 バイトまでに限る（先頭は数字以外）。
[tests/default.nix](../../tests/default.nix) は、Home Manager 側の名前のデータベースを Postgres が作ることを確かめる。

データベースはそのユーザーが所有し、Unix socket の peer 認証で接続する。パスワードは使わない。
nixpkgs の `ensureDBOwnership` はユーザーと同じ名前のデータベースにしか使えないので、所有者は `postgresql-setup` の最後に `ALTER DATABASE` で付ける。
拡張は所有者には作れないので、同じ所で superuser として作る。pgvector と PGroonga の control ファイルには `trusted = true` がなく、superuser でないロールは `CREATE EXTENSION` を実行できない（Postgres 17.11、pgvector 0.8.2、PGroonga 4.0.5、nixpkgs 26.05 の 4feb8eb で確認）。superuser が拡張を作ったデータベースを一般ロールに所有させれば、そのロールで migrate、全文検索、距離計算が通る。xsaved の migrate の `CREATE EXTENSION IF NOT EXISTS` は、作成済みなら何もしない。

拡張を作るには superuser が要るので、Home Manager だけではデータベースを用意できない。
`local.xsaved` は NixOS の Home Manager モジュールとして使うときだけ有効にでき、Home Manager を単独で使う構成では assertion で止まる。

Postgres のメジャー版は 17 に固定する。既定値は `system.stateVersion` で決まり、メジャー版が変わるとデータディレクトリの移行が要るからである。

データディレクトリは既定の `/var/lib/postgresql/17`（NVMe）のままにする。
データベースに入るのは本文、メタデータ、OCR の文字、ベクトル（ツイート 1 件あたり ruri が 3KB と Qwen が 8KB、画像 1 枚あたり 8KB）で、メディアは入らない。
検索はランダム読みになるので、disk-tiering.md の分け方ではホット層に当たる。

## GPU を使う計算はロックで順番にする

二つの実行が同時に埋め込みのモデルを VRAM に載せると、どちらかが足りなくなる。
夜間の `xsaved-process` と手で始めた `xsaved embed` が重なったときや、同じホストのほかのユーザーが使ったときに起きる。
[modules/nixos/xsaved.nix](../../modules/nixos/xsaved.nix) が、ロックファイル `/run/xsaved-gpu.lock` を tmpfiles で作り、`xsaved-env` が `XSAVED_GPU_LOCK` でその場所を渡す。
`xsaved embed` は、計算の前にこのファイルの排他ロックを取り、ほかの実行が終わるまで待つ。

ロックファイルは root が持つ 0644 のファイルにする。flock は読み取りで開いたファイルにも掛けられるので、どのユーザーも使え、消したり書き換えたりはできない。
検索は、モデルを読み込むときにロックを待たずに試す。夜間の画像の埋め込みは数時間かかるので、検索を待たせると使えなくなる。
ロックを取れなければ、検索サーバーはモデルを読み込まず、モデルを使う列にその旨を表示する。全文検索と似たツイートの検索は GPU を使わないので動く。
ロックを取れた検索サーバーは、モデルを載せている間（終了するまで）ロックを持つので、後から始まった `xsaved embed` は検索サーバーが止まるまで待つ。検索サーバーは最後のリクエストから 15 分で止まるので、待つのは最大 15 分である。

ほかのユーザーは、データベースの名前を別にすれば、同じホストで使える。
[tests/default.nix](../../tests/default.nix) は、二人のユーザーがマウントのないホストで使う構成が評価を通ることを確かめる。

## アカウント名をリポジトリに書かない

いいね欄を取得する X のアカウント名は、データディレクトリの `x-user` から `xsaved-env` が読む。
このリポジトリは公開しているので、Nix の設定に書くと GitHub のアカウントと X のアカウントが結び付く。

## checkout をそのまま実行する

`xsaved` は `local.xsaved.projectDir` の checkout を `uv run --project ... --frozen` で実行する。
ML の依存（ROCm 版の torch の wheel など）は xsaved の `uv.lock` で決まっていて、Nix のパッケージにすると uv の lock と二重に管理することになる。

`xsaved` は、埋め込みと OCR を使うサブコマンド（`ocr`、`embed`、`search`、`serve`）のときだけ `--extra ml` を付ける。
ほかのサブコマンドでは uv が ML の依存を取得も更新もしないので、ROCm 版の torch の取得や更新に失敗しても、ツイートの取得と登録は続く。
`uv run` は `--exact` を付けなければ、指定されていない extra のパッケージを venv から消さないので、venv は一つで足りる。

`projectDir` は本番用の checkout で、開発用の checkout（nixos-desktop では `~/sagyo/xsaved`）とは分ける。
定期実行は起動時に `xsaved migrate` も実行するので、開発用の checkout を実行すると、未コミットの変更や作業中のブランチが保存済みのデータに作用する。
nixos-desktop では、本番用の checkout を `~/sagyo` の外の `~/.local/share/xsaved-app` に置き、開発のつもりで編集しにくくする。
サブボリュームの中に置かないのは、新しいマシンでサブボリュームのマウント前に clone すると、マウントがその checkout を隠すからである。
`pull-repos` の対象にも入れない。入れると、`pull-repos` がバックアップを取らずに本番用の checkout を更新する。
本番用の checkout は `xsaved-update` で更新する。新しいコミットは次の定期実行の起動時に `xsaved migrate` でスキーマを変えるので、`xsaved-update` は定期実行を止め、取り込む直前の状態をバックアップしてから `git pull --ff-only` を実行する。

スキーマの変更を取り込み忘れないよう、二つのサービスはどちらも始めに `xsaved migrate` を実行する。
二つが同時に始まっても同じ SQL を二度流さないよう、xsaved の migrate は Postgres の advisory lock を取る。

## 定期実行

[xsaved.nix](../../modules/home-manager/xsaved.nix) が取得、OCR・埋め込み、バックアップの systemd user timer を定義する。

`xsaved-sync` は毎時、いいね欄とブックマーク欄と、返信先と引用元を取得して登録する。
gallery-dl は取得済みのツイートが 20 件続いたら止まるので、普段の実行は数秒から十数秒で終わる。
初回は取得済みのツイートがないので、それぞれの欄を最後まで辿る。前の実行が終わるまで、timer は次の実行を始めない。

`xsaved-process` は毎日 4:00 に、本文の埋め込み、OCR、画像の埋め込み、タグ付け（PixAI Tagger）、新しいタグの別名の取得（Danbooru）、本文の埋め込みの順で実行する。別名の取得はネットワークを使う。
GPU を使う計算を、ゲームなどと重なりにくい時刻に寄せる。
本文の埋め込みは数分で終わるので先に済ませ、取り込んだ直後から意味検索できるようにする。
OCR の文字は ruri の入力に入るので、最後にもう一度本文を埋め込む。入力が変わったツイートだけが計算される。
OCR は CPU の全コアを使うので、`Nice=19` と `IOSchedulingClass=idle` で前面のアプリに譲る。
`Persistent=true` なので、電源が切れていて逃した分は、ユーザーのサービスマネージャーが次に起動したときに実行される。
nixos-desktop では pomu を linger にしているので、ログインを待たずに OS の起動時に実行される（[tailscale.md](./tailscale.md#ログインしていなくてもユーザーの-timer-を動かす)）。

`xsaved-sync`、`xsaved-process`、`xsaved-backup` には `X-SwitchMethod = "keep-old"` を付け、switch のときに動いていれば入れ替えない。新しい定義は次の実行から使われる。
Home Manager の sd-switch は、定義が変わって動いているユニットを止めて起動し直し、oneshot の起動が終わるまで待つ。2026-10-23 に、取り込み直後の長い `xsaved-process` の途中で switch したところ、処理を最初からやり直し、`home-manager-pomu.service` が 5 分で時間切れになった。

## 退けた案

- mimikopi-env を汎用化して両方から使う。上の「FHS 環境を mimikopi-env と分ける」に書いた理由で、今は退けた。
- xsaved を Nix のパッケージや flake input にする。上の「checkout をそのまま実行する」に書いた理由で退けた。
- 取得と登録用の venv と ML 用の venv を分ける。ML のサブコマンドが uv の同期に失敗して venv を中途半端に書き換えても、取得と登録を巻き込まずに済むが、venv の場所と uv の設定が二組になるので退けた。
- Postgres のデータディレクトリを `@xsaved` に置く。`@xsaved` は `nofail` でマウントするので、マウントされていないときにルート側へ初期化させない仕組みが別に要る。データベースは NVMe に置ける大きさなので退けた。
- Postgres をユーザーの systemd サービスで動かす。データディレクトリをユーザーが持てるが、起動、拡張の読み込み、更新を自分で書くことになる。NixOS のモジュールで足りるので退けた。

## 代償

`xsaved` と、xsaved の環境の Python を使うものは、`xsaved-env` の中で実行する必要がある。
`@xsaved` がマウントされていない間は、`xsaved-env` は何も実行せずに止まり、定期実行は失敗として記録される。
ROCm 版の torch を、耳コピの環境と別に持つ。

## Web UI は使うときだけ起動する

検索語をベクトルにするには、ruri と Qwen3-VL-Embedding を読み込む必要があり、GPU で約 5〜6 GiB、CPU だとメモリを同じだけ使い、読み込みに約 40 秒かかる。
検索はときどき使うだけなので、モデルを読み込んだまま常駐させると、使わない時間の VRAM が無駄になる。
そこで、ブラウザで開いたときに systemd のソケットから起動し、使われなくなったら止める。

xsaved の `xsaved serve` は、ポートを開いて待ち受けるだけの普通のサーバーで、systemd からソケットを受け取る作りにはしていない。
代わりに、`xsaved-web.socket` が受けた接続を `systemd-socket-proxyd` が次のポートのサーバーへ渡す。
`systemd-socket-proxyd` は `--exit-idle-time=15min` で終わり、サーバーは `StopWhenUnneeded` なので、プロキシが終わると一緒に止まる。
サーバーに、ソケットを受け取る処理と、しばらく使われなければ終わる処理を書かずに済む。
サーバーが待ち受けを始める前にプロキシが接続すると失敗するので、サーバーの `ExecStartPost` でポートが開くまで待つ。

検索語のベクトルは GPU で計算する。モデルを読み込むのはサーバーが起動してから最初の検索だけで、似たツイートの検索はモデルを使わない。
結果は検索方法ごとの列に並べ、RRF でまとめない。理由は xsaved の `docs/design.md` にある。
検索サーバーは GPU のロックを待たずに試し、取れたら終了するまで持つ（[GPU を使う計算はロックで順番にする](#gpu-を使う計算はロックで順番にする)）。

nixos-desktop では、ポート番号を覚えずに開けるよう、常駐する Caddy を `http://xsaved.localhost/` の入口にする。
名前は `/etc/hosts` でループバックへ解決し、Caddy も IPv4・IPv6 のループバックだけで待ち受ける。
転送先は Home Manager の `local.xsaved.webPort` を参照する。サーバー本体へ直接転送するとソケットによる起動を迂回するため、既存の起動用ソケットへ渡す。
自マシン内の HTTP 接続とし、証明書の配布は行わない。Tailscale 経由でノート PC から開けるようにするのは、あとで決める。

## バックアップを Google Drive に restic で写す

X で消えたツイートは取り直せない。like.js の取り込みでも、29,611 件のうち 2,698 件がすでに取得できなかった。
保存したデータが唯一の写しになるので、`xsaved-backup` が毎日 6:00 に、保存先の SATA SSD とは別の場所へ写す。

写すのは、取得したツイート（`tweets/`、メタデータとメディア）、データベース全体のダンプ、埋め込みモデル（`huggingface/hub`）、写したときの flake_public と xsaved のコミットの記録（`backup/revisions`）である。
データベースのうち `tweets/` から作り直せないのは、最初に見つけた日時（`first_seen_at`）だけだが、OCR の文字と埋め込みのベクトルを作り直すには GPU で約 1 日かかる。
ダンプは約 1.2 GB で、全体を写しても Drive の空き（約 340 GiB）に対して小さいので、丸ごと写して復元を一度の読み込みで済ませる。
ダンプは圧縮しない形式にする。圧縮すると、一行増えただけでも後ろのバイト列がすべて変わり、restic が前の日の写しと重なる部分を再利用できなくなる。
uv の環境は uv.lock から作り直せるので写さない。
埋め込みモデルは、配布元が消すと同じモデルを取り直せず、保存済みのベクトルと比べる検索ができなくなるので写す。ruri と Qwen を合わせて約 5 GB で、Drive の空きに対して小さい。

`xsaved-backup` は、写す前に書き込みのロックを排他で取る。`xsaved` コマンドは、`status`、`search`、`similar`、`serve` 以外のサブコマンドで同じロックを共有で取る。
取得や計算が書き込んでいる途中で写すと、データベースのダンプとファイルが別の時点の状態になるからである。
バックアップは書き込み中の処理が終わるのを待ち、写している間に始まろうとした処理はバックアップが終わるまで待つ。毎日 6:00 の数分だけ、その時刻の `xsaved-sync` が遅れる。
`serve` がロックを取らないのは、何時間も動くことがあり、取るとバックアップが始まらないからである。

`xsaved-restore-check` は、最新のバックアップから復元できるかを、本番のデータとデータベースに触れずに確かめる。
ダンプを一時的な Postgres に読み込み、件数、全文検索の索引、ベクトルの比較を確かめる。
`tweets/` は約 26 GB あり、保存先の SATA SSD にもルートにも丸ごと戻す空きがないので、メディアは全ファイルがスナップショットにあることを一覧で確かめ、一部だけ戻して中身のハッシュをデータベースと照合する。

restic のリポジトリは Google Drive に直接置き、restic の rclone バックエンドで読み書きする。
Minecraft のバックアップのように手元の `/mnt/backup` にリポジトリを置いて Drive へ `rclone sync` で写す形は、手元の写しが保存先と同じ SATA SSD に乗るので、ディスクの故障には役に立たない。
Minecraft で手元に置いた理由（ゲームの終了時の待ち時間を Drive の遅さに左右させない）は、夜中に定時で動く処理には当てはまらない。

世代は GFS（日次 7、週次 4、月次 12）で残す。最新の状態だけを写すと、手元で消えたり壊れたりしたデータが次の写しにも反映される。データは追加がほとんどなので、世代を残しても増える容量は小さい。
写しは restic で暗号化する。X ではいいねは本人にしか見えないので、何にいいねしたかの一覧は非公開の情報で、ダンプには X のアカウント名も入る。
パスワードは `secrets/secrets.yaml` に sops で暗号化して置き、Home Manager の secrets が switch のたびに `~/.config/xsaved/restic-password` へ書き出す。パスワードを別に保管する必要はなく、age 鍵（Bitwarden にもある）があれば取り戻せる。

退けた案:

- `tweets/` を `rclone sync` でそのまま Drive に写す。世代が残らず、手元で消えたファイルは Drive からも消える。暗号化するには rclone の crypt を別に設定する必要がある。
- 手元の `/mnt/backup` に restic のリポジトリを置き、Drive へ写す。上に書いた理由で、手元の写しは役に立たず、SATA SSD の容量を約 25 GB 使う。

## 未確定

- いいねが増えたときのデータベースの大きさ。ベクトルの索引（HNSW）を作るかどうかと合わせて、実データで決める。
