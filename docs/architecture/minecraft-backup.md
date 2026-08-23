# Minecraft バックアップ（設計判断）

設定ファイル:
- `modules/home-manager/minecraft-backup.nix`（コマンド 4 本の定義とオプション、`mc-sync` のタイマー）
- `modules/home-manager/minecraft-common.sh`（各コマンドの先頭に連結される共通部分）
- `modules/home-manager/minecraft-{backup,check,restore,sync}.sh`（各コマンドの本体）
- `hosts/nixos-desktop/home-manager-pomu.nix`（リポジトリ位置・送り先の注入）
- `hosts/nixos-desktop/data-disk.nix`（`/mnt/backup/minecraft` の作成）

使い方は [../howtouse/minecraft-backup.md](../howtouse/minecraft-backup.md) を参照。

## 背景

ワールドデータは失うと代替がきかない一方、PrismLauncher のインスタンスには復元に不要な
ものが大量に混ざる。手で取っていた時点で、インスタンス 2.4G に対し必要な部分は 689M だった。
差の大半は `minecraft/backups`（ゲーム内バックアップ）と `logs` / `cache`。

## 発火をタイマーではなく post-exit フックにした

バックアップ自動化の一般的な形は systemd timer / cron による定時実行だが、PrismLauncher には
`PostExitCommand` という設定項目があり、`INST_ID` / `INST_NAME` / `INST_DIR` / `INST_MC_DIR` が
環境変数で渡る。これを使うと

- 遊んだ直後、つまり変化があったときだけ走る
- 対象インスタンスは既に終了しているので、書き込み途中のワールドを掴まない
- 終了したインスタンスだけを対象にできる（全インスタンス走査が要らない）

の 3 つが同時に得られる。定時実行で同じ性質を得るには「起動中でないか」「前回以降に
saves が変化したか」の判定を自前で持つことになる。

取りこぼしはある。クラッシュや強制終了ではフックが走らない。次に遊んで正常終了したときに
拾われるので、失われるのはクラッシュしたセッション 1 回分。

## ZIP をやめて restic にした

以前はインスタンスを丸ごと ZIP に固めていた。人間が Drive の Web UI から中身を覗いて世代を
選べる形を優先した判断だったが、次の 2 点で行き詰まった。

計測したところ、日をまたいだ 2 つの ZIP は 923 ファイル 451 MiB が CRC まで一致していた。
1 回 507 MiB のうち実際に変わるのは 34 ファイル 56 MiB で、89% が前日と同じ中身。遊ぶたびに
これを丸ごと積んで丸ごと送る。Drive への実測は 3.211 MiB/s なので、507 MiB の転送に約 2.6 分。
ランチャーはフックの完了を待つので、この時間そのままインスタンスが実行中の表示で残る。

restic は content-defined chunking で重複を排除し、圧縮もかかる。変わった分しか積まないので、
同じ保存容量ならはるかに長い履歴が残る。転送も差分だけになり、post-exit の待ち時間が縮む。

代償として Drive 側は人間が読めない形になり、復元に `restic restore` が要る。Drive の役割を
「冗長コピー」と定めたので、覗ける必要は無いと判断した。

## Drive のリポジトリはホストごとに分ける

デスクトップとラップトップの両方から同じワールドを遊ぶため、Drive を経由して状態を運ぶ。
このとき 2 台が同じ restic リポジトリへ書くと、後から `rclone sync` した側が相手の世代を
消してしまう（`sync` は削除も伝播するため）。

そこで `gdrive:minecraft-backups/<hostname>/` のようにホスト名でリポジトリを分ける。各マシンは
自分の領域にしか書かず、他のマシンの領域は読むだけ。これで書き込みの衝突が原理的に起きない。

排他制御（ロックやリース）を置く案も検討したが、要らなくなった。ラップトップを持ち出すのは
旅行や帰省で、そのときデスクトップは電源が入っていない。同時刻に両方が書く状況が無いので、
必要なのは「相手の方が新しいときに気づく」ことだけ。それは各リポジトリの最新スナップショット
時刻を読み比べれば済む（`mc-check`）。

分けた副作用として、同じワールドの履歴が 2 系統に分かれる。合流はしないが、どちらも消えない
ので安全側に倒れている。

## 手元のリポジトリが正本で、Drive は写し

`mc-backup` はまず手元の restic リポジトリへ取り込み、その後 `rclone sync` で Drive へ写す。
Drive へ直接 restic で書く形（`restic -r rclone:...`）も取れるが、採らなかった。

- ネットが無い旅行先でもバックアップが成立する。Drive への転送が失敗しても、手元には既に
  入っているので後で `mc-sync` が拾う
- restic の操作が Drive のレイテンシに引きずられない。post-exit の待ち時間に直接効く

`mc_push` は `rclone sync` の前に `$MC_REPO/config` の存在を確かめる。リポジトリが空だったり
壊れていたりする状態で `sync` を走らせると、Drive 側を消してしまうため。

## 世代の刈り込みは保持ポリシーで行い、容量では自動削除しない

`--keep-last=3 --keep-daily=14 --keep-weekly=8 --keep-monthly=12` を既定にしている。
GFS（世代管理の一般的な形）そのままで、直近は密に、過去は疎に残す。

`--group-by host,tags` を付けてインスタンスごとに数える。これが無いと、よく遊ぶワールドの
世代が、放置しているワールドの世代を押し出す。

容量が上限を超えたら古い方から消す、という形は採らなかった。保持ポリシーと綱引きになり、
どの世代が残るかが遊んだ量に左右されて読めなくなる。上限（`warnAtGiB`、既定 10）は警告
だけを出し、実際にどうするかはユーザーが決める。

## リポジトリにパスワードを付けない

`--insecure-no-password` を使っている。ワールドデータは秘密ではなく、Drive にあるのは
既に自分のアカウントの中。一方でパスワードを付けると、それをどこに置くかという問題が出る。
このリポジトリには sops / agenix のような秘密管理の仕組みが無いので、置き場所は平文の
ファイルか Nix store（= world-readable）になり、実質的な保護にならない。

秘密管理を導入したら再検討する余地はある。

## `mc-check` は Drive を読めないとき通す

pre-launch フックは非ゼロで返すと起動を止める。ネットが無いときに止めると、旅行先で
遊べなくなる。Drive の一覧が取れなければ、その旨を出して 0 で返す。

守りたいのは「デスクトップの続きをラップトップで上書きしてしまう」事故で、これは家に
いてネットがあるときに起きる。オフラインでの誤爆は、そもそも相手の状態を知りようが
ないので防げない。

## `mc-restore` は取り込んだ後に手元へも記録する

`mc-restore` の最後で `mc_backup_instances` を呼び、取り込んだ状態を手元のリポジトリにも
スナップショットとして入れる。これが無いと、手元の最新スナップショットが復元前のまま
古く残り、`mc-check` が「相手の方が新しい」と言い続けて起動を止める。

`restore --target /` は絶対パスへ書き戻し、`--delete` でスナップショットに無いファイルを
消す。事故の範囲が読めないので、実行前にスナップショットの `paths` が全て `$MC_INSTANCES`
の下を指すことを確かめている。

## リポジトリ位置と送り先はモジュールに直書きせず注入する

`options.local.minecraftBackup` を宣言し、`repoDir` と `remote` はホスト側で設定する
（`modules/home-manager/gui/apps.nix` の `options.local.insecurePackages` と同じ形）。
空き容量のあるパーティションはホストごとに違い、`/mnt/backup` は nixos-desktop にしか無い。

`repoDir` と `remote` には既定値を置いていない。既定を置くと、書けない場所や存在しない
remote へ黙って向かう。`enable = true` にした側が必ず指定する形にしている。

`instancesDir` だけは既定を持つ。PrismLauncher が決めるパスなのでホスト差が無い。

ホスト名は Nix のオプションにせず、実行時に `/etc/hostname` から読む。オプションにすると
実際のホスト名とずれる余地ができ、ずれた瞬間に別マシンの領域へ書き込む。

## リポジトリを NVMe ではなく SATA の `@backup` に置く

`/` は 423G 中 76G しか空いておらず、履歴を積む先には向かない。SATA の `@backup`
subvol は空き 144G で、[disk-tiering.md](./disk-tiering.md) が「NVMe の退避先」と位置づけて
いる場所そのもの。書き込み一度・読み出し稀なので SATA で体感差は出ない。

restic は自前で圧縮するので btrfs の `compress=zstd` は素通りする。

SATA は単一ディスクで冗長性が無い。Drive 側の写しが冗長コピーにあたる。

`/mnt/backup/minecraft` 直下には restic 移行前の ZIP が残っている。restic には取り込んで
いない履歴なので消さず、リポジトリは `repo/` サブディレクトリに置いて分けている。

## flake の共通モジュールに入れず、ホストから直接 import する

`flake.nix` の `homeModules`（全ホスト共通）に足して `features` でトグルする形も取れるが、
1 ホストしか使わない機能のためにトグルを増やすと共通側の分岐が太る。prismlauncher 自体が
`hosts/nixos-desktop/home-manager-pomu.nix` で宣言されているので、同じ場所から import する。

ラップトップ（nixos-spin713）ではまだ有効にしていない。有効にすると prismlauncher も
一緒に入るので、実際に持ち出して遊ぶと決めたときに足す。

## 書き込み先ディレクトリを tmpfiles で用意する

`/mnt/backup` は root 所有なので、そのままではユーザーのコマンドが書けない。
`sudo chown` を手順書に書くのではなく、`data-disk.nix` の `systemd.tmpfiles.rules` で
`/mnt/backup/minecraft` を `primaryUser` 所有で作る。マシンを作り直しても同じ状態になる。
`repo/` はその下なので `restic init` が自分で作れる。

`/mnt/backup` 直下は root のまま残している。用途が増えたときに所有者を分けられるようにする
ため。`systemd-tmpfiles-setup` は `local-fs.target` の後に走るので、マウント前の root
ファイルシステム側にディレクトリができてマウントに隠される事故は起きない。

## `prismlauncher.cfg` は Nix 管理にしない

`PostExitCommand` / `PreLaunchCommand` の設定先である `prismlauncher.cfg` は、アプリが
ウィンドウ位置や最後に使ったインスタンスを頻繁に書き戻すファイル。home-manager の
`home.file` で置くと store 上の読み取り専用シンボリックリンクになり、アプリ側の書き込みが
壊れる。GUI で一度設定し、手順を使い方ドキュメントに残す形にしている。

## post-exit コマンドを切り離さない

ランチャーはコマンドの完了を待つので、その間インスタンスが実行中の表示のまま残る。
`setsid` 等で切り離せばこの待ちは消えるが、失敗したときに気づく手段が無くなる。
バックアップが静かに失敗するのが最悪なので、待つ側を選んでいる。restic にしたことで
待ち時間自体は短くなった。

## 共通部分をシェル関数として切り出し、ビルド時に連結する

4 つのコマンドは同じ環境変数・同じインスタンス走査・同じ Drive パス規則を使う。
`minecraft-common.sh` に置き、`mkCommand` が各本体の先頭に `builtins.readFile` で連結する。

別コマンドとして `mc-common` を作って `source` する形は取らなかった。store パスを実行時に
解決する必要が出て、`writeShellApplication` の shellcheck も追えなくなる。連結なら
1 ファイルとして検査される。

## `writeShellApplication` で包む

GUI から起動されたランチャーの子プロセスとして走るので、PATH に何が入っているかが読めない。
`runtimeInputs` で `restic` / `rclone` / `jq` / `procps` 等の store パスを PATH 前置し、環境に
依存しないようにしている。副産物としてビルド時に shellcheck が通り、`errexit` / `nounset` /
`pipefail` が入る。

指定したインスタンス ID が一つも当たらない場合は非ゼロで終わる。打ち間違いを黙って
「何もしなかった」で済ませないため。起動中によるスキップは正常終了にする（失敗ではなく、
フック経由では起こらない状況なので）。
