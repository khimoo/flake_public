# Minecraft バックアップの設計

使い方: [Minecraft バックアップ](../howtouse/minecraft-backup.md)
実装: [minecraft-backup.nix](../../modules/home-manager/minecraft-backup.nix)、[minecraft-common.sh](../../modules/home-manager/minecraft-common.sh) と各コマンドの本体

## 終了時のフックで取り込む

PrismLauncher の `PostExitCommand` は、`INST_ID` などを環境変数で渡して終了後に実行される。
これを使うと、遊んで変化があったときだけ、終了して書き込みの止まったインスタンスだけを取り込める。
定時実行で同じことをするには、起動中かどうかと前回から `saves` が変わったかを自前で判断することになる。
クラッシュや強制終了ではフックが実行されないが、失うのはそのセッションの分だけで、次に正常に終了したときに取り込まれる。

コマンドは切り離さず、ランチャーに完了を待たせる。`setsid` などで切り離すと待ち時間は消えるが、失敗しても気づけなくなる。

## ZIP ではなく restic にする

インスタンスを丸ごと ZIP にすると、日をまたいだ 2 つの ZIP で 507 MiB のうち 451 MiB（89%）が前日と同じ中身だった。
遊ぶたびにそれを丸ごと積んで送り、Drive への転送（3.211 MiB/s）に約 2.6 分かかり、その間ランチャーは待たされる。
restic は重複を除いて圧縮するので、変わった分だけを積んで送る。

代償として、Drive の中身は人が Web UI で覗けず、戻すには `restic restore` が要る。Drive の役割は写しなので、覗けなくてよいと判断した。

## Drive のリポジトリはマシンごとに分ける

同じワールドをデスクトップとラップトップで遊ぶので、状態を Drive 経由で運ぶ。
2 台が同じリポジトリへ書くと、後から `rclone sync` したほうが相手の世代を消す。
そこで `gdrive:minecraft-backups/<ホスト名>/` に分け、各マシンは自分の領域にだけ書く。

排他制御は置かない。ラップトップを持ち出すのは旅行や帰省のときで、デスクトップの電源は切れている。
要るのは相手のほうが新しいと気づくことだけで、それは各リポジトリの最新スナップショットの時刻を比べれば足りる（`mc-check`）。
同じワールドの履歴は 2 系統に分かれるが、どちらも消えない。

ホスト名はオプションにせず、実行時に `/etc/hostname` から読む。オプションにすると実際のホスト名とずれる余地ができ、ずれると別のマシンの領域へ書き込む。

## 手元のリポジトリを正本にし、Drive は写しにする

`mc-backup` は手元のリポジトリへ取り込んでから `rclone sync` で Drive へ写す。Drive へ直接 restic で書く形は退けた。
ネットのない旅行先でも取り込めて、restic の操作が Drive の遅さに左右されないため。
`rclone sync` の前に `$MC_REPO/config` があるかを確かめる。空や壊れたリポジトリで `sync` すると、Drive 側を消すため。

リポジトリは SATA の `@backup` subvol（`/mnt/backup`）に置く。`/` の NVMe は空きが少なく、書き込みが一度で読むことの少ないデータなので SATA で足りる（[disk-tiering.md](./disk-tiering.md)）。
SATA は 1 台で冗長性がないので、Drive の写しがその役を担う。

## 世代は保持ポリシーで消し、容量では消さない

`--keep-last=3 --keep-daily=14 --keep-weekly=8 --keep-monthly=12` を既定にし、`--group-by host,tags` でインスタンスごとに数える。
まとめて数えると、よく遊ぶワールドの世代が、放置しているワールドの世代を押し出す。

容量が上限を超えたら古い順に消す形は退けた。保持ポリシーとぶつかり、どの世代が残るかが遊んだ量で変わって読めなくなる。
上限（`warnAtGiB`）は警告だけにし、どうするかはユーザーが決める。

## リポジトリにパスワードを付けない

`--insecure-no-password` を使う。ワールドは秘密ではなく、Drive の写しも自分のアカウントの中にある。
パスワードを付けるなら、xsaved のバックアップと同じく `secrets/secrets.yaml` から配れる。

## `mc-check` は Drive を読めないとき通す

起動前のフックが非ゼロで返すと起動が止まり、ネットのない旅行先で遊べなくなる。
Drive の一覧が取れなければ、その旨を出して 0 で返す。
防ぎたいのは、デスクトップの続きをラップトップで上書きする事故で、これはネットのある家で起きる。

## `mc-restore` は取り込んだ状態を手元にも記録する

`mc-restore` の最後に、取り込んだ状態を手元のリポジトリにもスナップショットとして入れる。
入れないと手元の最新スナップショットが古いまま残り、`mc-check` が相手のほうが新しいと言い続けて起動を止める。

`restore --target /` は絶対パスへ書き戻し、`--delete` でスナップショットにないファイルを消す。
実行する前に、スナップショットの `paths` がすべて `$MC_INSTANCES` の下を指すことを確かめる。

## リポジトリの場所と送り先はホストで指定する

`repoDir` と `remote` には既定値を置かない。既定があると、書けない場所や存在しない remote へ黙って向かう。
`/mnt/backup` は nixos-desktop にしかない。
`instancesDir` は PrismLauncher が決めるパスなので既定を持つ。

`/mnt/backup` は root のものなので、`data-disk.nix` の tmpfiles が `repoDir` の親を primaryUser のものとして作る。
`/mnt/backup` の直下は、用途ごとに所有者を分けられるよう root のまま残す。
tmpfiles は `local-fs.target` の後に実行されるので、マウント前のルートにディレクトリができてマウントに隠されることはない。

モジュールは全ホスト共通の `homeModules` に入れず、PrismLauncher を宣言している `home-manager-pomu.nix` から import する。1 ホストのためのトグルを共通の側に増やさないため。

## `prismlauncher.cfg` は Nix で管理しない

PrismLauncher はウィンドウの位置や最後に使ったインスタンスをこのファイルに書き戻す。`home.file` で置くと読み取り専用の symlink になり、書き込みが壊れる。
`mc-setup-hooks` が `[General]` のフックの 2 行だけを書き換える。

## 共通部分はビルド時に連結する

4 つのコマンドは同じ環境変数、インスタンスの走査、Drive のパスの規則を使う。
`minecraft-common.sh` を各本体の先頭に `builtins.readFile` で連結し、1 つのファイルとして shellcheck を通す。
別のコマンドを `source` する形は、store パスを実行時に解決することになり、shellcheck も追えなくなるので退けた。

GUI から起動したランチャーの子プロセスとして動くので、PATH に何があるか分からない。`writeShellApplication` の `runtimeInputs` で `restic` や `rclone` を PATH に入れる。
