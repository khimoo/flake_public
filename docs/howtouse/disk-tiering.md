# ディスク階層構成

nixos-desktop では、高速な NVMe（`/`、`/nix/store`、`~/sagyo`）と SATA SSD を使い分けています。高速アクセスを必要としないデータは、SATA ドライブ上の Btrfs サブボリューム（subvol）へ配置します。

設計ドキュメント: [ディスク階層構成の設計](../architecture/disk-tiering.md)

## ディスクレイアウト

各サブボリュームの用途およびマウント設定の定義場所は以下の通りです。

- **`@personal`（マウント先: `/mnt/personal`）**
  個人用ディレクトリ（`~/ダウンロード`、`~/Games` など）を格納します。[personal_folders.star](../../config/elements/personal_folders.star) により、全ユーザーの `<ユーザー名>/downloads` などのディレクトリが各ホームディレクトリへ bind mount されます。マウント前に `personal-folders-<ユーザー名>` サービスがディレクトリを自動生成するため、手動で作成する必要はありません。
- **`@backup`（マウント先: `/mnt/backup`）**
  バックアップ用領域です。[machine_nixos_desktop.star](../../config/elements/machine_nixos_desktop.star) 内の `mounts` でマウントが定義されています。
- **`@vm`、`@mimikopi`、`@xsaved`**
  各コンポーネント（[windows_vm_images.star](../../config/elements/windows_vm_images.star)、[mimikopi.star](../../config/elements/mimikopi.star)、[xsaved_data.star](../../config/elements/xsaved_data.star)）によってマウントされます。これら 3 つの subvol 名は `.star` ファイルではなく、ホストの TOML 設定ファイルで指定します。
  - `@vm`: `windows_vm_images_subvolume`
  - `@mimikopi`: `mimikopi_data_subvolume`
  - `@xsaved`: `[users.xsaved]` セクションの `data_subvolume`

なお、`@mimikopi` と `@xsaved` は該当アプリケーションを有効化した後に手動で作成する subvol です。未作成の状態でもシステムの起動が妨げられないよう、マウントオプションに `nofail` が付与されています。

## 状態の確認

```sh
sudo btrfs filesystem usage /mnt/backup    # 圧縮後の実使用量と空き容量の確認（df コマンドは圧縮前の値を表示するため注意）
sudo btrfs subvolume list /mnt/backup      # subvol の一覧を表示
findmnt -t btrfs                            # 現在の Btrfs マウント状態を確認
lsattr -d /var/lib/libvirt/images           # @vm が NOCOW に設定されているか確認（'C' フラグが立っていれば有効）
```

## 新しい subvol の追加手順

1. ドライブを一時的にマウントし、subvol を作成します。

   ```sh
   sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
   sudo nix shell nixpkgs#btrfs-progs -c btrfs subvolume create /mnt/sda/@newname
   sudo chown pomu:users /mnt/sda/@newname     # ホームディレクトリ配下にマウントする場合
   sudo umount /mnt/sda
   ```

2. `config/elements/machine_nixos_desktop.star` の `mounts` に `("@newname", "/path/to/mount", data_opts)` を追記します。
3. 設定を反映します。

   ```sh
   sudo nixos-rebuild switch --flake .#nixos-desktop
   ```

> [!NOTE]
> VM イメージ用など CoW（Copy on Write）を無効化したい subvol の場合は、作成直後の空の状態で `sudo chattr +C /mnt/sda/@newname` を実行し、マウントオプション `opts` から `compress=zstd` を除外してください。

## 既存データを持つユーザーを追加する手順

個人フォルダを bind mount すると、NVMe 上の同名ディレクトリ内にあった既存ファイルはマウントによって隠れてしまいます。
そのため、ホストの TOML にユーザーを追加する前に、対象ユーザーをログアウトさせた上でデータを SATA ドライブ側へ移行します。

1. SATA ドライブ側に対象ユーザー用のディレクトリを作成し、データを退避します。

   ```sh
   sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
   sudo install -d -m 0700 -o <ユーザー名> -g users /mnt/sda/@personal/<ユーザー名>
   sudo cp -a /home/<ユーザー名>/ダウンロード /mnt/sda/@personal/<ユーザー名>/downloads
   # ビデオ（videos）、音楽（music）、画像（pictures）、ドキュメント（documents）、Games（games）も同様に移行
   sudo umount /mnt/sda
   ```

2. `nixos-rebuild switch` と再起動を実施し、正常にマウントされたことを確認した後に NVMe 側の元データを削除します。
   ※マウントによって隠れてしまった元ファイルを確認・削除する場合は、ルートファイルシステムを一時的に bind mount することでアクセス可能です。

   ```sh
   sudo mkdir -p /mnt/rootfs && sudo mount --bind / /mnt/rootfs
   # /mnt/rootfs/home/<ユーザー名>/ダウンロード 等からアクセス可能
   ```

## Steam ゲームライブラリを SATA ドライブへ配置する

`~/Games` は SATA ドライブ上の `@personal/<ユーザー名>/games` にマウントされていますが、Steam のデフォルトインストール先は NVMe 上の `~/.local/share/Steam/steamapps` となっています。SATA ドライブ側を利用するには手動で設定を変更します。

1. Steam を起動し、「設定」→「ストレージ」を開きます。
2. ドライブのドロップダウンメニューから「ドライブを追加」を選び、`~/Games` を指定します。
3. 追加したライブラリを選択し、「デフォルトに設定」を有効にします。

すでにインストール済みのゲームは、「プロパティ」→「インストール済みファイル」→「インストールフォルダーの移動」からライブラリ間を移動できます。

## SATA ドライブの初期化と再構築

> [!CAUTION]
> 以下の操作を実行すると、`/dev/sda` 内のデータはすべて消去されます。

```sh
# 対象が正しい SATA ドライブ（sda）であることを必ず確認
lsblk -o NAME,SIZE,MODEL /dev/sda

# パーティションテーブルの初期化と作成
sudo wipefs -a /dev/sda
sudo nix shell nixpkgs#gptfdisk -c sgdisk --zap-all /dev/sda
sudo nix shell nixpkgs#gptfdisk -c sgdisk -n 1:0:0 -t 1:8300 -c 1:data /dev/sda
sudo nix shell nixpkgs#btrfs-progs -c mkfs.btrfs -f -L data /dev/sda1

# 基本 subvol の作成
sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
sudo nix shell nixpkgs#btrfs-progs -c bash -c \
  'for s in personal vm backup; do btrfs subvolume create /mnt/sda/@$s; done'
sudo chattr +C /mnt/sda/@vm

# UUID の確認（出力結果をホスト TOML の data_device に設定）
sudo blkid -s UUID -o value /dev/sda1
```

※ `sudo nix shell` で対話シェルに入ると環境変数 `PATH` が引き継がれずコマンドが見つからなくなる可能性があるため、`-c` オプションを用いて直接実行してください。
構築後はバックアップ等から各 subvol へ `rsync` でデータをリストアし、NVMe 側のマウントポイントを空にしてから `nixos-rebuild switch` を実行してください（マウント先にファイルが残っていると、隠れたまま NVMe の容量を圧迫し続けます）。
`@mimikopi` および `@xsaved` は、必要に応じて「[新しい subvol の追加手順](#新しい-subvol-の追加手順)」に従って作成してください。
