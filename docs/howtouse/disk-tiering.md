# ディスク階層構成

nixos-desktop では NVMe（`/`、`/nix/store`、`~/sagyo`）と SATA SSD を使い分け、高速アクセスを必要としないデータを SATA ドライブ上の btrfs サブボリューム（subvol）に配置しています。
個人フォルダ（`~/ダウンロード`、`~/Games` など）は [personal_folders.star](../../config/elements/personal_folders.star) が、`personal_files` を選んだ利用者ごとに、`@<アカウント名>-downloads` のような subvol をホームへ直接マウントします。`@backup` のマウント先（`/mnt/backup`）は [machine_nixos_desktop.star](../../config/elements/machine_nixos_desktop.star) 内の `mounts` で定義されています。`@vm`、`@mimikopi`、`@xsaved` は、使う要素（[windows_vm_images.star](../../config/elements/windows_vm_images.star)、[mimikopi.star](../../config/elements/mimikopi.star)、[xsaved_data.star](../../config/elements/xsaved_data.star)）が、ホストのファイルの `windows_vm_images_subvolume`、`mimikopi_data_subvolume`、利用者の表（`[users.xsaved]`）の `data_subvolume` からマウントします。

設計ドキュメント: [ディスク階層構成の設計](../architecture/disk-tiering.md)

## ディスクレイアウト

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

2. `config/elements/machine_nixos_desktop.star` の `mounts` に `("@newname", "/path/to/mount", data_opts)` を追記します。
3. `sudo nixos-rebuild switch --flake .#nixos-desktop` を実行します。

※ VM イメージ用など CoW（Copy on Write）を回避したい subvol の場合は、作成直後の空の状態で `sudo chattr +C /mnt/sda/@newname` を実行し、マウントオプション `opts` から `compress=zstd` を外してください。

## 個人フォルダを持つ利用者を追加する

個人フォルダの subvol は、起動時に必ずマウントされます（`nofail` なし）。subvol がないと起動が緊急モードで止まるので、利用者の `purposes` に `personal_files` を足す前に、その利用者の subvol を 6 つ作ります。

```sh
sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
sudo nix shell nixpkgs#btrfs-progs -c bash -c \
  'for s in downloads videos music pictures documents games; do btrfs subvolume create /mnt/sda/@<アカウント名>-$s; done'
sudo chown <アカウント名>:users /mnt/sda/@<アカウント名>-*
sudo umount /mnt/sda
```

## Steam ゲームライブラリを SATA ドライブへ配置する

`~/Games` は SATA ドライブ上の `@pomu-games` にマウントされていますが、Steam は自動的にこれを使用せず、デフォルトでは NVMe 上の `~/.local/share/Steam/steamapps` にゲームをインストールします。

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
  'for s in pomu-downloads pomu-videos pomu-music pomu-pictures pomu-documents pomu-games vm backup; do btrfs subvolume create /mnt/sda/@$s; done'
sudo chattr +C /mnt/sda/@vm
sudo chown pomu:users /mnt/sda/@pomu-*    # 個人フォルダの subvol は @<アカウント名>-<名前>

sudo blkid -s UUID -o value /dev/sda1    # 出力された UUID をホストの TOML の data_device に設定する
```

※ `nix shell` は `-c` を使って直接コマンドを実行してください。`sudo` から `nix shell` の対話シェルに入ると PATH が正常に引き継がれず、コマンドが見つからなくなる原因になります。
構築後、バックアップ等から各 subvol へ `rsync` でデータを移行し、NVMe 側の元のデータを削除・空にしてから `switch` を実行してください。
`@mimikopi` と `@xsaved` については、前述の「[新しい subvol の追加手順](#新しい-subvol-の追加手順)」に沿って別途作成してください。
