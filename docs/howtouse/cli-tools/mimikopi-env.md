# mimikopi-env

耳コピ（楽曲の自動採譜）スキルで使う ML モデルを、uv 環境下で動かすためのコマンドです。
nixos-desktop にのみ導入されています。
[home-manager-pomu.nix](../../../hosts/nixos-desktop/home-manager-pomu.nix) の `local.mimikopi` で有効化し、データ保存先（`dataDir`）や GPU 互換性の指定（`hsaOverrideGfxVersion`）もそちらで設定します。

設計: [mimikopi-env の設計](../../architecture/mimikopi-env.md)

## 初回準備

データは SATA SSD のサブボリューム（subvol）`@mimikopi` に配置します。
subvol は自動作成されないため、[disk-tiering.md の「新しい subvol の追加手順」](../disk-tiering.md#新しい-subvol-の追加手順) に沿って初回のみ手動で作成してください。
`@mimikopi` 用の具体例コマンドは以下の通りです。

```sh
sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
sudo nix shell nixpkgs#btrfs-progs -c btrfs subvolume create /mnt/sda/@mimikopi
sudo chown pomu:users /mnt/sda/@mimikopi
sudo umount /mnt/sda
sudo nixos-rebuild switch --flake .#nixos-desktop
```

マウント定義には `nofail` オプションが付与されているため、subvol 作成前に `switch` やシステムの再起動を行っても起動処理は停止しません。
その場合は、subvol を作成した後に再起動するか、以下のコマンドで手動マウントしてください。

```sh
sudo systemctl start home-pomu-.local-share-mimikopi.mount
```

## 使い方

```bash
mimikopi-env
mimikopi-env uv run --no-project --python 3.11 python -c 'import sys; print(sys.version)'
```

引数なしで実行すると環境内のシェルに入り、`exit` で抜けることができます。
引数を指定した場合は、そのコマンドのみを環境内で実行します。
以下の環境変数は環境内部でセットされるため、環境外のシェルから渡す引数の中で `$MIMIKOPI_DATA_DIR` などを記述すると、変数が空のまま展開されてしまいます。変数を使用する際は `mimikopi-env bash -c '...'` のように環境内部で展開されるよう記述してください。
モデル環境をデータディレクトリ内のどこに展開するかは、耳コピスキル側で制御します。
なお、モデル環境内の Python は環境外から直接呼び出すと `Could not start dynamically linked executable` エラーとなり起動しません。

## 環境内での変更点

ライブラリ、PATH、`/etc`、`sudo` の取り扱いは [uv-mode](./uv-mode.md#モード内での変化点) と同様です。
`/usr/lib` に見えるライブラリには、ROCm 版 PyTorch が読み込む `libzstd`、`libdrm`、`libnuma`、`libelf`、`liblzma`、`libbz2` が追加されています。
また、`ffmpeg` も利用可能です。

設定される環境変数（データディレクトリ配下の配置場所、`MIMIKOPI_DATA_DIR`、`HSA_OVERRIDE_GFX_VERSION` など）は [packages/mimikopi-env](../../../packages/mimikopi-env/default.nix) に定義されています。データディレクトリの実体は `~/.local/share/mimikopi`（`@mimikopi` のマウント先）です。

## マウントされていない場合

`@mimikopi` がマウントされていない場合、処理は何も実行されず、以下のエラーメッセージを出力して停止します。

```text
mimikopi-env: /home/pomu/.local/share/mimikopi がマウントされていません。手順: docs/howtouse/cli-tools/mimikopi-env.md
```

`findmnt /home/pomu/.local/share/mimikopi` で状態を確認し、subvol が存在しない場合は「初回準備」の手順を実施してください。
subvol が存在するもののマウントされていない場合は、上記の `systemctl start` コマンドでマウントしてください。

## ライブラリが不足している場合

wheel をインポートした際に `cannot open shared object file` エラーが発生した場合は、該当するライブラリを含むパッケージを [packages/mimikopi-env](../../../packages/mimikopi-env/default.nix) の `targetPkgs` に追記してください。
