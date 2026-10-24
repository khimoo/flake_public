# ディスク階層構成の設計

使い方: [ディスク階層構成](../howtouse/disk-tiering.md)
実装: [data-disk.nix](../../hosts/nixos-desktop/data-disk.nix)

nixos-desktop の NVMe（Samsung 980、466G）が 94% まで埋まったので、Windows 用だった SATA SSD（Samsung 860、233G）を全部消してデータの層にし、SATA で遅くならないデータを NVMe から移した。
分ける基準は、SSD かどうかではなく、そのデータの IO の形である。SATA が NVMe にはっきり負けるのは、小さいファイルへのランダムアクセスで、シーケンシャルな読み書きやネットワークで律速されるものは差がほとんど出ない。

## `/nix/store` は NVMe に置く

store は switch、GC、optimise で数万の小さいファイルにランダムにアクセスするので、NVMe が最も効く。SATA に移すと、switch の IO の部分が 2〜5 倍遅くなりうる。
起動と activation のごく初めに要るので、別のデバイスに分けるのも難しい。

## SATA に移すのはディスクの速度が効かないデータだけ

- papis のライブラリ: 同期はネットワーク（Google Drive）で律速される
- 動画、音楽、画像、ダウンロード: 再生は数〜数十 MB/s で、SATA のシーケンシャル（約 550MB/s）に十分収まる
- VM のイメージ: デスクトップ用途の VM は起動時にまとめて読み、その後はほとんど page cache に載る。VM の中で重いデータベースやビルドを動かすなら別
- バックアップ: 一度書いて、まれにしか読まない
- Steam のゲーム: 1 本で数十 GB になり NVMe を最も削るが、ロードは大きなアセットのシーケンシャルな読み込みが中心。ロードが気になるタイトルは、そのゲームだけ NVMe 側のライブラリへ移す

## SATA は btrfs にする

データとバックアップの層なので、チェックサム（めったに読まないデータのビットの腐りを検出できる）、snapshot、subvol（1 つのパーティションを用途ごとに分けられる）を使える。
zstd の圧縮も付けているが、対象の多く（jpg、mp4、mp3、PDF）はすでに圧縮されているので、容量の効果は小さい。

`@vm` だけは NOCOW にする。CoW のままだと VM のイメージが激しく断片化して遅くなるので、subvol のルートに `chattr +C` を付け、後から作るイメージに継承させる。NOCOW のファイルには圧縮もチェックサムも効かないので、`compress=zstd` は付けない。

## subvol は最終パスへ直接マウントする

`~/ダウンロード` などを bind mount や symlink で間接にせず、subvol をそのパスへ直接マウントする。アプリから見たパスは変わらず、中身だけが SATA に載る。
fileSystems は `{ subvol, path, opts }` のリストから生成し、device と fsType を一か所にまとめる。

`@papis` は `~/sagyo/zettelkasten/references`（NVMe の vault の clone の中）にマウントする。
papis のライブラリの場所は workflow の flake が `<vaultDir>/references` に固定しているので、マウントでその保存先だけを SATA に差し替える。
papis を vault の中に置くことと、SATA に置くことを両立させる形で、papis の層が保存先を知らない向き（[papis-gdrive-sync.md](./papis-gdrive-sync.md)）とも合う。

## `@papis` だけは vault があるときだけマウントする

`fileSystems` に書くと、systemd は起動時にマウント先を無条件に作り、root のものの中間ディレクトリができる。
すると `clone-repos` の `git clone` が「空でないディレクトリ」で失敗し、`dest` があるので以後の実行では飛ばされて、vault が届かないまま気づけない。実際にこうなった。
そこで `@papis` だけ `systemd.mounts` にし、`ConditionPathExists = "${zettelkastenRoot}/.git"` を付ける。
clone の後は `.git` の出現を見る path unit がマウントを始めるので、再起動は要らない。
条件が偽の間、`references/` は vault がないのと同じ状態なので、NVMe 側に書き込まれる事故は起きない。

## データの層のマウントに `nofail` を付けない

データは SATA にしかないので、マウントの失敗を `nofail` で隠すと、NVMe 上の空のマウント先にアプリが書き込み、データがないことにも気づけない。
内蔵ディスクで常にある前提なので、失敗したら起動で気づける既定のままにする。

例外は、アプリを有効にしてから手で作る `@mimikopi` と `@xsaved` で、作る前の switch や再起動で起動を止めないよう `nofail` を付ける。
代わりに、使う側の環境（`mimikopi-env`、`xsaved-env`）が起動時にマウントを確かめ、マウントされていなければ止まる。
アプリの保存先は primaryUser の Home Manager の設定（`local.mimikopi.dataDir`、`local.xsaved.dataDir`、`local.minecraftBackup.repoDir`、`local.quaderno.archiveDir`）から読み、アプリが有効なときだけマウントや tmpfiles を用意する。
`@backup` は複数のアプリが共有するので、依存の向きが逆になる。
マウント先は `data-disk.nix` の `local.dataDisk.backupDir` に一度だけ書き、Minecraft と Quaderno の保存先は Home Manager の設定が `osConfig` からこの値を読んで作る。

## Steam のライブラリは Steam に登録させる

repo が持つのは `~/Games` が SATA を指すところまでで、Steam のライブラリへの登録は Steam の設定で行う。
登録先の一覧の `libraryfolders.vdf` は、Steam が容量やアプリ ID を書き換える状態のファイルなので、`home.file` で置くと読み取り専用の symlink になり、Steam の書き込みが失敗する。

## 起動時の世代メニューは残す

起動時に出る OS の選択画面は、systemd-boot の世代のメニューで、復旧の手段なので残す。
SATA にあった旧 Windows は UEFI のエントリも `/boot/EFI/Microsoft` もなく、すでに起動できない状態だったので、消すべきデュアルブートの仕組みはなかった。
`boot.loader.timeout = 0` は、メニューを出さない設定ではない。メニューを隠すが、キーを押すと出てきて、そのときはタイムアウトが効かなくなる。即座に起動させる手段には使わない。
