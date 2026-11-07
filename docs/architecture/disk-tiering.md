# ディスク階層構成の設計

使い方: [ディスク階層構成](../howtouse/disk-tiering.md)
実装: [data-disk.nix](../../hosts/nixos-desktop/data-disk.nix)

nixos-desktop の NVMe（Samsung 980、466G）が 94% まで埋まったので、Windows 用だった SATA SSD（Samsung 860、233G）を全部消してデータの層にし、SATA で遅くならないデータを NVMe から移した。
分ける基準は、SSD かどうかではなく、そのデータの IO の形である。SATA が NVMe にはっきり負けるのは、小さいファイルへのランダムアクセスで、シーケンシャルな読み書きやネットワークで律速されるものは差がほとんど出ない。

## `/nix/store` は NVMe に置く

store は switch、GC、optimise で数万の小さいファイルにランダムにアクセスするので、NVMe が最も効く。SATA に移すと、switch の IO の部分が 2〜5 倍遅くなりうる。
起動と activation のごく初めに要るので、別のデバイスに分けるのも難しい。

## SATA に移すのはディスクの速度が効かないデータだけ

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

## マウントの起動順序の循環は check で見つける

以前は `@papis` を vault の clone の中にマウントし、path unit から起動していた。そのとき `nofail` のないマウントと path unit の間で起動順序が循環し、systemd がジョブを取り消した起動では GDM が起動しなかった。
起動順序の循環は評価でもビルドでも見つからないので、check の `systemd-ordering`（[tests/default.nix](../../tests/default.nix)）が、各ホストのユニットと fstab から作るマウントで `systemd-analyze verify` を実行し、循環があれば失敗する。

## データの層のマウントに `nofail` を付けない

データは SATA にしかないので、マウントの失敗を `nofail` で隠すと、NVMe 上の空のマウント先にアプリが書き込み、データがないことにも気づけない。
内蔵ディスクで常にある前提なので、失敗したら起動で気づける既定のままにする。

例外は、アプリを有効にしてから手で作る `@mimikopi` と `@xsaved` で、作る前の switch や再起動で起動を止めないよう `nofail` を付ける。
代わりに、使う側の環境（`mimikopi-env`、`xsaved-env`）が起動時にマウントを確かめ、マウントされていなければ止まる。
mimikopi のマウント先と Minecraft・Quaderno の tmpfiles のパスは `data-disk.nix` に指定する。アプリ側の保存先は [nixos-desktop.toml](../../config/hosts/nixos-desktop.toml) の `mimikopi_data_dir`、`minecraft_repo`、`quaderno_archive` にあるため、変更時は両方を合わせる。xsaved の保存先も `data-disk.nix` と同じホストファイルの `xsaved_users` の `data_dir` に指定するため、変更時は両方を合わせる。
`@backup` は複数のアプリが共有し、マウント先は `data-disk.nix` の `local.dataDisk.backupDir` で指定する。

## Steam のライブラリは Steam に登録させる

repo が持つのは `~/Games` が SATA を指すところまでで、Steam のライブラリへの登録は Steam の設定で行う。
登録先の一覧の `libraryfolders.vdf` は、Steam が容量やアプリ ID を書き換える状態のファイルなので、`home.file` で置くと読み取り専用の symlink になり、Steam の書き込みが失敗する。

## 起動時の世代メニューは残す

起動時に出る OS の選択画面は、systemd-boot の世代のメニューで、復旧の手段なので残す。
SATA にあった旧 Windows は UEFI のエントリも `/boot/EFI/Microsoft` もなく、すでに起動できない状態だったので、消すべきデュアルブートの仕組みはなかった。
`boot.loader.timeout = 0` は、メニューを出さない設定ではない。メニューを隠すが、キーを押すと出てきて、そのときはタイムアウトが効かなくなる。即座に起動させる手段には使わない。
