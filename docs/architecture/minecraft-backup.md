# Minecraft バックアップ（設計判断）

設定ファイル:
- `modules/home-manager/minecraft-backup.nix`（`mc-backup` の定義とオプション）
- `modules/home-manager/minecraft-backup.sh`（本体）
- `hosts/nixos-desktop/home-manager-pomu.nix`（出力先・送り先の注入）
- `hosts/nixos-desktop/data-disk.nix`（`/mnt/backup/minecraft` の作成）

使い方は [../howtouse/minecraft-backup.md](../howtouse/minecraft-backup.md) を参照。

## 背景

ワールドデータは失うと代替がきかない一方、PrismLauncher のインスタンスには復元に不要な
ものが大量に混ざる。手で取っていた時点で、インスタンス 2.4G に対し必要な部分は 689M だった。
差の大半は `minecraft/backups`（ゲーム内バックアップ）と `logs` / `cache`。

## 発火をタイマーではなく post-exit フックにした

バックアップ自動化の一般的な形は systemd timer / cron による定時実行で、NixOS の
`services.restic.backups` も既定は日次。ただしそれが成り立つのは restic / borg が差分・
重複排除型だからで、変化が無い日に走らせても保存量も転送量もほぼゼロになる。

ここは毎回フル ZIP を作り直すので、その前提が無い。定時実行にすると遊ばなかった日も
689M を作って送る。逆に PrismLauncher には `PostExitCommand` という設定項目があり、
`INST_ID` / `INST_NAME` / `INST_DIR` / `INST_MC_DIR` が環境変数で渡る。これを使うと

- 遊んだ直後、つまり変化があったときだけ走る
- 対象インスタンスは既に終了しているので、書き込み途中のワールドを掴まない
- 終了したインスタンスだけを対象にできる（全インスタンス走査が要らない）

の 3 つが同時に得られる。定時実行で同じ性質を得るには「起動中でないか」「前回以降に
saves が変化したか」の判定を自前で持つことになる。

取りこぼしはある。クラッシュや強制終了ではフックが走らない。保険として低頻度のタイマーを
併置する余地は残っている。

## 形式は ZIP のままにした（restic にしない）

標準に寄せるなら restic + 日次タイマーが本筋で、重複排除・世代管理・暗号化がついてくる。
採らなかったのは、Drive を人間が覗いて世代を選ぶ運用と噛み合わないため。restic リポジトリは
Drive 上で読めない形になり、復元に `restic restore` が要る。ZIP なら Drive の Web UI から
中身が見えるし、`unzip` だけで戻せる。

代償として重複排除が無く、遊ぶたびフル ZIP が積み上がる。世代の刈り込みは手動のまま
残っている（[../howtouse/minecraft-backup.md](../howtouse/minecraft-backup.md)）。

## 出力先を NVMe ではなく SATA の `@backup` に置く

`/` は 423G 中 76G しか空いておらず、1 回で 689M を積む先には向かない。SATA の `@backup`
subvol は空き 144G で、[disk-tiering.md](./disk-tiering.md) が「NVMe の退避先」と位置づけて
いる場所そのもの。書き込み一度・読み出し稀なので SATA で体感差は出ない。

`compress=zstd` が効いているが ZIP は既圧縮なので btrfs 側が自動でスキップする。

SATA は単一ディスクで冗長性が無い。正本は Drive 側にあり、ローカルは中間置き場という
位置づけ。

## 出力先と送り先はモジュールに直書きせず注入する

`options.local.minecraftBackup` を宣言し、`outDir` と `remote` はホスト側で設定する
（`modules/home-manager/gui/apps.nix` の `options.local.insecurePackages` と同じ形）。
空き容量のあるパーティションはホストごとに違い、`/mnt/backup` は nixos-desktop にしか無い。

`outDir` と `remote` には既定値を置いていない。既定を置くと、書けない場所や存在しない
remote へ黙って向かう。`enable = true` にした側が必ず指定する形にしている。

`instancesDir` だけは既定を持つ。PrismLauncher が決めるパスなのでホスト差が無い。

## flake の共通モジュールに入れず、ホストから直接 import する

`flake.nix` の `homeModules`（全ホスト共通）に足して `features` でトグルする形も取れるが、
1 ホストしか使わない機能のためにトグルを増やすと共通側の分岐が太る。prismlauncher 自体が
`hosts/nixos-desktop/home-manager-pomu.nix` で宣言されているので、同じ場所から import する。

## 書き込み先ディレクトリを tmpfiles で用意する

`/mnt/backup` は root 所有なので、そのままではユーザーの `mc-backup` が書けない。
`sudo chown` を手順書に書くのではなく、`data-disk.nix` の `systemd.tmpfiles.rules` で
`/mnt/backup/minecraft` を `primaryUser` 所有で作る。マシンを作り直しても同じ状態になる。

`/mnt/backup` 直下は root のまま残している。用途が増えたときに所有者を分けられるようにする
ため。`systemd-tmpfiles-setup` は `local-fs.target` の後に走るので、マウント前の root
ファイルシステム側にディレクトリができてマウントに隠される事故は起きない。

## `prismlauncher.cfg` は Nix 管理にしない

`PostExitCommand` の設定先である `prismlauncher.cfg` は、アプリがウィンドウ位置や最後に
使ったインスタンスを頻繁に書き戻すファイル。home-manager の `home.file` で置くと store 上の
読み取り専用シンボリックリンクになり、アプリ側の書き込みが壊れる。GUI で一度設定し、
手順を使い方ドキュメントに残す形にしている。

## post-exit コマンドを切り離さない

ランチャーはコマンドの完了を待つので、`1.21` では 1〜2 分インスタンスが実行中の表示のまま
残る。`setsid` 等で切り離せばこの待ちは消えるが、失敗したときに気づく手段が無くなる。
バックアップが静かに失敗するのが最悪なので、待つ側を選んでいる。

## `writeShellApplication` で包む

GUI から起動されたランチャーの子プロセスとして走るので、PATH に何が入っているかが読めない。
`runtimeInputs` で `zip` / `rclone` / `procps` の store パスを PATH 前置し、環境に依存しない
ようにしている。副産物としてビルド時に shellcheck が通り、`errexit` / `nounset` / `pipefail`
が入る。

指定したインスタンス ID が一つも当たらない場合は非ゼロで終わる。打ち間違いを黙って
「何もしなかった」で済ませないため。起動中によるスキップは正常終了にする（失敗ではなく、
フック経由では起こらない状況なので）。
