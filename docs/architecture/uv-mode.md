# uv-mode の導入

[howtouse/cli-tools/uv-mode.md](../howtouse/cli-tools/uv-mode.md) の設計判断。

## 使いみち

会社の Python プロジェクトは uv で依存を固定し（`uv.lock`）、Python 3.8 から 3.14 までの互換を確かめている。
uv が取得する Python（python-build-standalone）と PyPI の manylinux wheel は、一般的な Linux 向けに動的リンクされている。NixOS ではローダーが見つからず、そのままでは起動しない。
Nix の `python3` で venv を作れば Python は起動するが、wheel の拡張モジュールが `libstdc++.so.6` を見つけられない。2026-10-14 に nixos-desktop で、Nix の Python 3.13 に shapely 2.1.2 の wheel を入れると、`import shapely` が `ImportError: libstdc++.so.6: cannot open shared object file` で失敗した。
nixpkgs 26.05 には Python 3.8 がないので、3.8 の確認には uv が取得する Python が要る。
プロジェクトのリポジトリは Nix を使わない同僚と共有しているので、shell.nix や flake.nix はそこに置かない。

## FHS 環境をコマンドとして入れる

[packages/uv-mode](../../packages/uv-mode/default.nix) は buildFHSEnv で、uv と wheel が使うライブラリ（zlib、libstdc++）を FHS の配置に並べた環境を作る。
一般的な Linux 向けのバイナリが動くのは、`uv-mode` で入った環境の中だけになる。
環境の中では `UV_PYTHON_PREFERENCE=only-managed` を設定し、uv が Nix の `python3` を選ばないようにする。
あわせて `IN_UV_MODE=1` を設定し、[dev/uv-mode.nix](../../modules/home-manager/dev/uv-mode.nix) の starship の `env_var.IN_UV_MODE` でプロンプトに `uv-mode` と表示する。モードの外で `uv sync` を実行し、ビルド用の一時環境の Python を起動できずに失敗したことがあったため、中にいるかを見分けられるようにした。変数名に `UV_` を付けないのは、uv が `UV_` で始まる環境変数を自分の設定として読むからで、Nix の `IN_NIX_SHELL` と同じ付け方にした。
Linux のホストでは [dev/uv-mode.nix](../../modules/home-manager/dev/uv-mode.nix) が Home Manager で入れるので、プロジェクト側には何も置かず、`nix develop` のような評価も毎回は走らない。
Home Manager の `pkgs.callPackage` でパッケージを組み立て、導入と Starship の表示を同じモジュールにまとめる。
パッケージ更新時は [検証ガイドの単体 build](../howtouse/validation.md#対象別の確認手順) を使う。
buildFHSEnv は Linux でしか作れないので、macOS の Home Manager には入れない。

2026-10-14 に nixos-desktop で確かめた結果:

- モードの中では、uv が取得した Python 3.14.6 に shapely 2.1.2 の wheel を入れて import できた。Python 3.8.20 も取得して起動できた。
- 同じ venv の `python` は、モードの外では `Could not start dynamically linked executable` で起動しなかった。
- モードの中でも、ホームディレクトリへの書き込み、名前解決、Home Manager のコマンド（`nvim`、`git`）は外と同じに使えた。`sudo` は no_new_privs のために失敗した。

同じ日に nixos-work-wsl（WSL2）でも確かめた。モードの中では `UV_PYTHON_PREFERENCE` が `only-managed` になり、uv が取得した Python 3.14.6 が起動したので、bubblewrap は WSL2 でも動く。

退けた案:

- nix-ld をシステムで有効にする。エディタを含めてどこからでも `.venv` の Python が動くが、uv 以外の配布バイナリも常に動くようになる。[antigravity-cli.md](./antigravity-cli.md) で nix-ld を退けたのと同じ理由になる。
- プロジェクトに shell.nix を置く。仕組みは同じだが、共有リポジトリに自分しか保守できないファイルが残る。
- direnv で devShell に入る（[devshells.md](./devshells.md) の方式）。direnv は環境変数を取り込むだけで、buildFHSEnv の名前空間には入れない。`mkShell` の devShell にはローダーがないので、uv が取得した Python は起動しない。
- devenv や uv2nix を使う。devenv はプロジェクト側に `devenv.nix` を置く前提になる。uv2nix は `uv.lock` から Nix で環境を組み立てるので、Python の取得と venv を uv に任せる運用と逆になる。

## 代償

`.venv` の Python を実行するもの（テスト、CLI、エディタの LSP）は、モードの中で起動する必要がある。
`/etc` はモード用に組み立て直したものになり、`/etc/ssh`、`/etc/nixos`、`/etc/inputrc` などホストの一部は見えない。nixos-work-wsl の `/etc/ssh` は NixOS の既定の内容だけで、会社の SSH 設定は `~/.ssh/config` に置く（[wsl.md](./wsl.md)）ので、git の接続には影響しない。
wheel がなくソースからビルドされる依存は、モードの中のライブラリに対してビルドされるので、モードの外では動かない。

## 未確定

- Windows 側の VS Code から WSL に接続して開発するか。VS Code のサーバー自体が配布バイナリで nix-ld を必要とするので、そうするなら nix-ld を有効にし、uv-mode は外す。
