# mimikopi-env

耳コピ（楽曲の自動採譜）スキルで使用する機械学習モデルを、uv 環境下で実行するためのコマンドです。
この環境は nixos-desktop にのみ導入されています。
[home-manager-pomu.nix](../../../hosts/nixos-desktop/home-manager-pomu.nix) の `local.mimikopi` で有効化し、データ保存先（`dataDir`）や GPU 互換性の指定（`hsaOverrideGfxVersion`）も同ファイル内で設定します。

設計: [mimikopi-env の設計](../../architecture/mimikopi-env.md)

## 初回準備

モデルや関連データは SATA SSD の Btrfs サブボリューム（subvol）`@mimikopi` に配置します。
この subvol は自動作成されないため、初回のみ [disk-tiering.md の「新しい subvol の追加手順」](../disk-tiering.md#新しい-subvol-の追加手順) に沿って手動で作成してください。
`@mimikopi` を作成するコマンド例は以下のとおりです。

```sh
sudo mkdir -p /mnt/sda && sudo mount /dev/sda1 /mnt/sda
sudo nix shell nixpkgs#btrfs-progs -c btrfs subvolume create /mnt/sda/@mimikopi
sudo chown pomu:users /mnt/sda/@mimikopi
sudo umount /mnt/sda
sudo nixos-rebuild switch --flake .#nixos-desktop
```

マウント設定には `nofail` オプションを指定しているため、subvol 作成前に `switch` やシステムの再起動を行ってもブート処理が停止することはありません。
その場合は subvol を作成した後にシステムを再起動するか、以下のコマンドで手動マウントしてください。

```sh
sudo systemctl start home-pomu-.local-share-mimikopi.mount
```

## 使い方

```bash
mimikopi-env
mimikopi-env uv run --no-project --python 3.11 python -c 'import sys; print(sys.version)'
```

引数なしで実行すると専用環境のシェルが起動し、`exit` で終了できます。
引数を指定した場合は、そのコマンドのみを環境内で実行します。
なお、関連する環境変数は環境内部で定義されるため、ホスト側のシェルから `$MIMIKOPI_DATA_DIR` などの引数を渡すと、変数が空のまま展開されてしまいます。環境変数を利用する際は、`mimikopi-env bash -c '...'` のように環境の内部で展開される形式で記述してください。
データディレクトリ内のどこにモデル環境を展開するかは、耳コピスキル側で制御します。
また、モデル環境内の Python をホスト環境から直接呼び出した場合、`Could not start dynamically linked executable` エラーが発生して起動できません。

## 環境内での変更点

- `/lib64/ld-linux-x86-64.so.2` や `/usr/lib` 配下の `libstdc++.so.6`、`libz.so.1` が認識されるようになり、一般的な Linux 向けバイナリをそのまま実行できます。
- PATH の先頭に `/usr/bin` が追加され、`uv`、`ls`、`grep` などは環境専用のものが優先されます。`nvim` や `git` のように環境に含まれないコマンドは、Home Manager のものがそのまま引き継がれます。
- `UV_PYTHON_PREFERENCE=only-managed` が設定され、uv は Nix が提供する `python3` を参照しなくなります。
- C コンパイラ用の環境変数（`NIX_CFLAGS_COMPILE` など）が `/usr` を参照します。wheel が提供されずソースからビルドされる依存パッケージは環境内のライブラリを前提にビルドされるため、ホスト環境上では動作しません。
- `/etc` は環境用に再構築された構成に置き換わるため、ホスト側の `/etc/ssh`、`/etc/nixos`、`/etc/inputrc` など一部のファイルは見えなくなります。
- `sudo` は権限変更不可フラグ（`no_new_privs`）の影響で失敗します。`nixos-rebuild` など権限昇格が必要な操作は環境外で実行してください。

ユーザー情報、ホームディレクトリ、`/nix`、`/tmp`、ネットワーク設定などはホスト環境と共通です。

mimikopi-env では、ROCm 版 PyTorch が読み込む `libzstd`、`libdrm`、`libnuma`、`libelf`、`liblzma`、`libbz2` が `/usr/lib` に配置されており、`ffmpeg` も利用可能です。

設定される環境変数（データディレクトリ配下の配置パス、`MIMIKOPI_DATA_DIR`、`HSA_OVERRIDE_GFX_VERSION` など）は [packages/mimikopi-env](../../../packages/mimikopi-env/default.nix) で定義されています。データディレクトリの実体は、`@mimikopi` のマウント先である `~/.local/share/mimikopi` です。

## マウントされていない場合

`@mimikopi` がマウントされていない場合、処理は実行されず、以下のエラーメッセージを出力して終了します。

```text
mimikopi-env: /home/pomu/.local/share/mimikopi がマウントされていません。手順: docs/howtouse/cli-tools/mimikopi-env.md
```

`findmnt /home/pomu/.local/share/mimikopi` で状態を確認し、subvol そのものが存在しない場合は「初回準備」の手順を実施してください。
subvol は存在するもののマウントされていない場合は、前述の `systemctl start` コマンドで手動マウントしてください。

## ライブラリが不足している場合

wheel のインポート時に `cannot open shared object file` エラーが発生した場合は、該当ライブラリを含むパッケージを [packages/mimikopi-env](../../../packages/mimikopi-env/default.nix) の `targetPkgs` に追加してください。
