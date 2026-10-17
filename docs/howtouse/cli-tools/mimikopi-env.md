# mimikopi-env

耳コピ（楽曲の自動採譜）のスキルが使う ML モデルを、uv の環境で動かすためのコマンド。
nixos-desktop だけに入る。
パッケージは [packages/mimikopi-env](../../../packages/mimikopi-env/default.nix) で、[home-manager-pomu.nix](../../../hosts/nixos-desktop/home-manager-pomu.nix) から入る。
設計判断は [architecture/mimikopi-env.md](../../architecture/mimikopi-env.md)。

## 初回の準備

データは SATA SSD の subvol `@mimikopi` に置く。
subvol は自動では作られないので、[disk-tiering.md の「新しい subvol を足す」](../disk-tiering.md#新しい-subvol-を足す)の手順で一度だけ作る。
`@mimikopi` に固有のコマンドは次のとおり。

```sh
sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
sudo nix shell nixpkgs#btrfs-progs -c btrfs subvolume create /mnt/sda/@mimikopi
sudo chown pomu:users /mnt/sda/@mimikopi
sudo umount /mnt/sda
sudo nixos-rebuild switch --flake .#nixos-desktop
```

マウント定義には `nofail` が付いているので、subvol を作る前に switch や再起動をしても起動は止まらない。
その場合は、subvol を作ってから再起動するか、次のコマンドでマウントする。

```sh
sudo systemctl start home-pomu-.local-share-mimikopi.mount
```

## 使い方

```bash
mimikopi-env
mimikopi-env uv run --no-project --python 3.11 python -c 'import sys; print(sys.version)'
```

引数なしで実行すると環境のシェルに入り、`exit` で抜ける。
引数を付けると、そのコマンドだけを環境の中で実行する。
下の環境変数は環境の中で設定されるので、外のシェルから渡す引数の中で `$MIMIKOPI_DATA_DIR` などを使うと、空のまま展開される。使うときは `mimikopi-env bash -c '...'` のように環境の中で展開させる。
モデルの環境をデータディレクトリのどこに置くかは、耳コピのスキルが決める。
モデルの環境の Python は、環境の外では `Could not start dynamically linked executable` で起動しない。

## 環境の中で変わること

ライブラリ、PATH、`/etc`、`sudo` の扱いは [uv-mode](./uv-mode.md#モードの中で変わること) と同じ。
`/usr/lib` に見えるライブラリには、ROCm 版の PyTorch が読む `libzstd`、`libdrm`、`libnuma`、`libelf`、`liblzma`、`libbz2` が加わる。
`ffmpeg` も使える。

次の環境変数が設定される。データディレクトリは `~/.local/share/mimikopi`（`@mimikopi` のマウント先）。

| 変数 | 値 | 用途 |
|------|----|------|
| `UV_PYTHON_PREFERENCE` | `only-managed` | uv に Nix の `python3` を選ばせない |
| `UV_CACHE_DIR` | `<データディレクトリ>/uv-cache` | uv のキャッシュ。モデルの環境と同じディスクに置き、ハードリンクで共有する |
| `UV_PYTHON_INSTALL_DIR` | `<データディレクトリ>/python` | uv が取得する Python |
| `HF_HOME` | `<データディレクトリ>/huggingface` | Hugging Face から取得するチェックポイント |
| `TORCH_HOME` | `<データディレクトリ>/torch` | PyTorch Hub から取得するチェックポイント |
| `MIMIKOPI_DATA_DIR` | `<データディレクトリ>` | スキルがモデルの環境を置く場所 |
| `HSA_OVERRIDE_GFX_VERSION` | `10.3.0` | ROCm に GPU を gfx1030 として扱わせる |

## マウントされていないとき

`@mimikopi` がマウントされていないと、何も実行せずに次のエラーで止まる。

```text
mimikopi-env: /home/pomu/.local/share/mimikopi がマウントされていません。手順: docs/howtouse/cli-tools/mimikopi-env.md
```

`findmnt /home/pomu/.local/share/mimikopi` で状態を確かめ、subvol が無ければ「初回の準備」を行う。
subvol があるのにマウントされていなければ、上の `systemctl start` でマウントする。

## ライブラリが足りないとき

wheel を import したときに `cannot open shared object file` が出たら、そのライブラリを含むパッケージを [packages/mimikopi-env](../../../packages/mimikopi-env/default.nix) の `targetPkgs` に足す。
