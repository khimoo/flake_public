# ディスク階層構成（使い方・セットアップ）

nixos-desktop は NVMe（ホット層）と SATA SSD（コールド/バルク層）の 2 台を使い分ける。
なぜこの構成かは [../architecture/disk-tiering.md](../architecture/disk-tiering.md) を参照。

設定ファイル: `hosts/nixos-desktop/data-disk.nix`

## レイアウト

SATA SSD（`/dev/sda`）は btrfs 単一パーティション。subvol を最終パスへ直接マウントする。

| subvol | マウント先 | オプション | 用途 |
|--------|-----------|-----------|------|
| `@papis` | `~/sagyo/zettelkasten/references` | `noatime,compress=zstd` | papis ライブラリ（vault 内・Google Drive 同期） |
| `@downloads` | `~/ダウンロード` | `noatime,compress=zstd` | ダウンロード |
| `@videos` | `~/ビデオ` | `noatime,compress=zstd` | 動画 |
| `@music` | `~/音楽` | `noatime,compress=zstd` | 音楽 |
| `@pictures` | `~/画像` | `noatime,compress=zstd` | 画像 |
| `@documents` | `~/ドキュメント` | `noatime,compress=zstd` | ドキュメント |
| `@vm` | `/var/lib/libvirt/images` | `noatime`（NOCOW） | libvirt の VM イメージ |
| `@backup` | `/mnt/backup` | `noatime,compress=zstd` | NVMe の退避先 |

全 subvol は FS 全体で 1 つの UUID を共有し、`subvol=@xxx` で選ぶ。

`@papis` だけはマウント先が vault clone の内側（`~/sagyo/zettelkasten/references`）にある。
マウント先の親 `~/sagyo/zettelkasten`（vault の clone）が先に存在している必要がある。
無いとマウントできず、papis のライブラリが空の NVMe ディレクトリに載ってしまう。
なぜ vault の中かつ SATA なのかは [../architecture/disk-tiering.md](../architecture/disk-tiering.md) を参照。

## 状態確認

```sh
# 実使用量（圧縮後）・空き。df は圧縮前の見かけ値なので btrfs 側で見る
sudo btrfs filesystem usage /mnt/backup      # 任意の btrfs マウントで可
sudo btrfs subvolume list /mnt/backup        # subvol 一覧

# マウント状況
findmnt -t btrfs

# @vm が NOCOW になっているか（C フラグが立っていれば OK）
lsattr -d /var/lib/libvirt/images
```

## 新しい subvol を足す

1. 一時マウントして subvol を作る:
   ```sh
   sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
   sudo nix shell nixpkgs#btrfs-progs -c btrfs subvolume create /mnt/sda/@newname
   sudo chown pomu:users /mnt/sda/@newname     # home 系なら
   sudo umount /mnt/sda
   ```
2. `hosts/nixos-desktop/data-disk.nix` の `mounts` リストに 1 行足す:
   ```nix
   { subvol = "@newname"; path = "/path/to/mount"; opts = dataOpts; }
   ```
3. `sudo nixos-rebuild switch --flake .#nixos-desktop`

VM のように CoW を避けたい subvol は、作成直後に空の状態で `sudo chattr +C /mnt/sda/@newname`
を実行し、`opts` から `compress=zstd` を外す。

## バックアップ運用（@backup）

`/mnt/backup` は NVMe の退避先。btrfs snapshot を送る、または restic のリポジトリ先に使う。
restic を使う場合は SATA を格納先にしつつ、暗号化・重複排除・世代管理を restic 側に任せ、
将来のオフサイト（別ロケーション）へも同じリポジトリを送れる。

## 初回セットアップ（参考: ディスクを一から作り直す場合）

`/dev/sda` を全消去して btrfs 化する手順。**sda の中身は完全に消える**。

```sh
# 消すのが sda(SATA)であることを目視確認
lsblk -o NAME,SIZE,MODEL /dev/sda

# 全消去 → 単一パーティション → btrfs（-c で直接実行。対話シェルに入ると PATH が壊れる）
sudo wipefs -a /dev/sda
sudo nix shell nixpkgs#gptfdisk -c sgdisk --zap-all /dev/sda
sudo nix shell nixpkgs#gptfdisk -c sgdisk -n 1:0:0 -t 1:8300 -c 1:data /dev/sda
sudo nix shell nixpkgs#btrfs-progs -c mkfs.btrfs -f -L data /dev/sda1

# subvol 作成
sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
sudo nix shell nixpkgs#btrfs-progs -c bash -c \
  'for s in papis downloads videos music pictures documents vm backup; do btrfs subvolume create /mnt/sda/@$s; done'
sudo chattr +C /mnt/sda/@vm
sudo chown pomu:users /mnt/sda/@papis /mnt/sda/@downloads /mnt/sda/@videos \
                      /mnt/sda/@music /mnt/sda/@pictures /mnt/sda/@documents

# UUID を data-disk.nix の device に反映
sudo blkid -s UUID -o value /dev/sda1
```

その後、既存データを各 subvol へ `rsync` で移し、NVMe 側の元データを空にしてから
`nixos-rebuild` で最終マウントを適用する。
