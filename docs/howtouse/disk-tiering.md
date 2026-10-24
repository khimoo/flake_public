# ディスク階層構成

nixos-desktop では NVMe（`/`、`/nix/store`、`~/sagyo`）と SATA SSD を使い分け、高速アクセスを必要としないデータを SATA ドライブ上の btrfs サブボリューム（subvol）に配置しています。
各 subvol のマウント先は [data-disk.nix](../../hosts/nixos-desktop/data-disk.nix) 内の `mounts` で定義されており、それぞれの最終パスへ直接マウントされます（`~/ダウンロード`、`~/Games`、`/var/lib/libvirt/images`、`/mnt/backup` など）。

設計ドキュメント: [ディスク階層構成の設計](../architecture/disk-tiering.md)

## ディスクレイアウト

`@papis` については vault のクローン内（`~/sagyo/memex/Assets/references`）にマウントするため、vault をクローンした状態（`~/sagyo/memex/.git` が存在する間）でのみマウントされます。
新しいマシンで `clone-repos` によって vault がクローンされると、`.git` の存在を検知する `papis-references.path` が動作し、自動的にマウントが開始されます。
マウントされていない場合は、ステータスを確認した上で手動でマウントしてください。

```sh
systemctl status papis-references.path home-pomu-sagyo-memex-Assets-references.mount
sudo systemctl start home-pomu-sagyo-memex-Assets-references.mount
```

`@mimikopi` と `@xsaved` は、該当アプリケーションを有効化した後に手動作成する subvol です。作成前であってもシステムの起動が停止しないよう `nofail` オプションが付与されています。

## 状態の確認

```sh
sudo btrfs filesystem usage /mnt/backup    # 圧縮後の実際の使用量と空き容量（df コマンドは圧縮前の値を表示するため注意）
sudo btrfs subvolume list /mnt/backup      # subvol の一覧を表示
findmnt -t btrfs                            # 現在のマウント状態を確認
lsattr -d /var/lib/libvirt/images           # @vm が NOCOW に設定されているか確認（'C' フラグが立っていれば OK）
```

## 新しい subvol の追加手順

1. ドライブを一時的にマウントし、subvol を作成します：

   ```sh
   sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
   sudo nix shell nixpkgs#btrfs-progs -c btrfs subvolume create /mnt/sda/@newname
   sudo chown pomu:users /mnt/sda/@newname     # ホームディレクトリー配下にマウントする場合
   sudo umount /mnt/sda
   ```

2. `data-disk.nix` の `mounts` 配下に `{ subvol = "@newname"; path = "/path/to/mount"; opts = dataOpts; }` を追記します。
3. `sudo nixos-rebuild switch --flake .#nixos-desktop` を実行します。

※ VM イメージ用など CoW（Copy on Write）を回避したい subvol の場合は、作成直後の空の状態で `sudo chattr +C /mnt/sda/@newname` を実行し、マウントオプション `opts` から `compress=zstd` を外してください。

## Steam ゲームライブラリを SATA ドライブへ配置する

`~/Games` は SATA ドライブ上の `@games` にマウントされていますが、Steam は自動的にこれを使用せず、デフォルトでは NVMe 上の `~/.local/share/Steam/steamapps` にゲームをインストールします。

1. Steam を起動し、「設定」→「ストレージ」→ ドライブのドロップダウンメニューから「ドライブを追加」を選び、`~/Games` を選択します。
2. 追加したライブラリを選択し、「デフォルトに設定」に変更します。

すでにインストール済みのゲームは、「プロパティ」→「インストール済みファイル」→「移動」からライブラリ間で移動できます。

## SATA ドライブを初期化して再構築する

**注意: `/dev/sda` 内のデータはすべて消去されます。**

```sh
lsblk -o NAME,SIZE,MODEL /dev/sda    # 消去対象が正しい SATA ドライブ（sda）であることを必ず目視確認する

sudo wipefs -a /dev/sda
sudo nix shell nixpkgs#gptfdisk -c sgdisk --zap-all /dev/sda
sudo nix shell nixpkgs#gptfdisk -c sgdisk -n 1:0:0 -t 1:8300 -c 1:data /dev/sda
sudo nix shell nixpkgs#btrfs-progs -c mkfs.btrfs -f -L data /dev/sda1

sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
sudo nix shell nixpkgs#btrfs-progs -c bash -c \
  'for s in papis downloads videos music pictures documents games vm backup; do btrfs subvolume create /mnt/sda/@$s; done'
sudo chattr +C /mnt/sda/@vm
sudo chown pomu:users /mnt/sda/@papis /mnt/sda/@downloads /mnt/sda/@videos \
                      /mnt/sda/@music /mnt/sda/@pictures /mnt/sda/@documents /mnt/sda/@games

sudo blkid -s UUID -o value /dev/sda1    # 出力された UUID を data-disk.nix の device 項目に設定する
```

※ `nix shell` は `-c` を使って直接コマンドを実行してください。`sudo` から `nix shell` の対話シェルに入ると PATH が正常に引き継がれず、コマンドが見つからなくなる原因になります。
構築後、バックアップ等から各 subvol へ `rsync` でデータを移行し、NVMe 側の元のデータを削除・空にしてから `switch` を実行してください。
`@mimikopi` と `@xsaved` については、前述の「[新しい subvol の追加手順](#新しい-subvol-の追加手順)」に沿って別途作成してください。
