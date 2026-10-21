# uv-mode

uv が取得する Python と manylinux wheel を NixOS で動かすための環境に入るコマンド。
共有リポジトリに shell.nix や flake.nix を置かずに、会社の Python プロジェクトを uv で開発するときに使う。
パッケージの定義は [packages/uv-mode](../../../packages/uv-mode/default.nix)。Linux のホストでは [dev/uv-mode.nix](../../../modules/home-manager/dev/uv-mode.nix) が `pkgs.callPackage` で導入し、Starship のモード表示も設定する。
パッケージ更新時は [検証ガイドの単体 build](../validation.md#対象別の確認手順) を使う。
設計判断は [architecture/uv-mode.md](../../architecture/uv-mode.md)。

## 使い方

```bash
uv-mode
uv-mode uv sync --all-packages
uv-mode nvim .
```

引数なしで実行するとモードのシェルに入り、`exit` で抜ける。
モードの中では、starship のプロンプトに `uv-mode` と表示される。
引数を付けると、そのコマンドだけをモードの中で実行する。
`.venv` の Python を実行するもの（テスト、CLI、エディタの LSP）は、モードの中で起動する。モードの外で `.venv/bin/python` を起動すると、`Could not start dynamically linked executable` で止まる。

## モードの中で変わること

- `/lib64/ld-linux-x86-64.so.2` と、`/usr/lib` の `libstdc++.so.6`、`libz.so.1` が見えるので、一般的な Linux 向けのバイナリが動く。
- PATH の先頭に `/usr/bin` が入り、`uv`、`ls`、`grep` などはモード用のものが使われる。`nvim` や `git` のようにモードに入れていないコマンドは、Home Manager のものが使われる。
- `UV_PYTHON_PREFERENCE=only-managed` が設定され、uv は Nix の `python3` を使わない。
- C コンパイラ向けの変数（`NIX_CFLAGS_COMPILE` など）が `/usr` を参照する。wheel がなくソースからビルドされる依存はモードの中のライブラリに対してビルドされ、モードの外では動かない。
- `/etc` はモード用に組み立て直したものになり、`/etc/ssh`、`/etc/nixos`、`/etc/inputrc` などは見えない。
- `sudo` は権限変更不可フラグ（no_new_privs）のために失敗する。`nixos-rebuild` はモードの外で実行する。

ユーザー、ホームディレクトリ、`/nix`、`/tmp`、ネットワークは外と同じ。
モードの中で作った `.venv` やファイルはそのまま残り、`~/.gitconfig` と `~/.ssh/config` もモードの中で使われる。

## ライブラリが足りないとき

wheel を import したときに `cannot open shared object file` が出たら、そのライブラリを含むパッケージを [packages/uv-mode](../../../packages/uv-mode/default.nix) の `targetPkgs` に足す。
