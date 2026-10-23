# uv-mode

uv が取得する Python や manylinux wheel を NixOS 上で動作させるための環境へ入るコマンドです。
共有リポジトリに `shell.nix` や `flake.nix` を配置せず、会社の Python プロジェクトを uv で開発する際に使用します。
パッケージ定義は [packages/uv-mode](../../../packages/uv-mode/default.nix) にあり、Linux ホストでは [dev/uv-mode.nix](../../../modules/home-manager/dev/uv-mode.nix) によって導入されます。パッケージを更新した際は、[検証ガイドの単体 build](../validation.md#対象別の確認手順) に従って動作を確認してください。

## 使い方

```bash
uv-mode
uv-mode uv sync --all-packages
uv-mode nvim .
```

引数なしで実行するとモード専用のシェルに入り、`exit` で抜けることができます。
モード内では、Starship のプロンプトに `uv-mode` と表示されます。
引数を指定すると、そのコマンドのみをモード内で実行します。
`.venv` 配下の Python を使用する処理（テスト実行、CLI、エディタの LSP など）は、必ずモード内で起動してください。モード外から `.venv/bin/python` を直接起動すると、`Could not start dynamically linked executable` と表示されて停止します。

## モード内での変化点

- `/lib64/ld-linux-x86-64.so.2` や `/usr/lib` 配下の `libstdc++.so.6`、`libz.so.1` が認識されるようになり、一般的な Linux 向けバイナリが動作します。
- PATH の先頭に `/usr/bin` が挿入され、`uv`、`ls`、`grep` などはモード用のものが使用されます。`nvim` や `git` のようにモードに含まれていないコマンドは、Home Manager のものが引き継がれます。
- `UV_PYTHON_PREFERENCE=only-managed` が設定され、uv は Nix が提供する `python3` を使用しなくなります。
- C コンパイラ用の環境変数（`NIX_CFLAGS_COMPILE` など）が `/usr` を参照します。wheel が存在せずソースからビルドされる依存パッケージはモード内のライブラリに対してビルドされるため、モード外では動作しません。
- `/etc` はモード用に再構築されたものに置き換わるため、`/etc/ssh`、`/etc/nixos`、`/etc/inputrc` などホスト側の一部は見えなくなります。
- `sudo` は権限変更不可フラグ（`no_new_privs`）の影響で失敗します。`nixos-rebuild` などはモード外で実行してください。

ユーザー情報、ホームディレクトリ、`/nix`、`/tmp`、ネットワーク設定などはモード外と共通です。
モード内で作成した `.venv` やファイルはそのまま保持され、`~/.gitconfig` や `~/.ssh/config` もそのまま利用できます。

## ライブラリが不足している場合

wheel をインポートした際に `cannot open shared object file` エラーが発生した場合は、該当するライブラリを含むパッケージを [packages/uv-mode](../../../packages/uv-mode/default.nix) の `targetPkgs` に追加してください。

## 設計

### 用途

会社の Python プロジェクトでは uv を用いて依存関係を固定し（`uv.lock`）、Python 3.8 から 3.14 までの互換性を検証しています。
uv が取得する Python（python-build-standalone）や PyPI の manylinux wheel は、一般的な Linux 環境向けに動的リンクされています。そのため、NixOS ではダイナミックリンカー（ローダー）が見つからず、そのままでは起動できません。
Nix の `python3` で venv を作成すれば Python 自体は起動しますが、今度は wheel のバイナリモジュールが `libstdc++.so.6` を参照できなくなります。実際、2026-10-14 に nixos-desktop 環境で Nix の Python 3.13 に shapely 2.1.2 の wheel をインストールしたところ、`import shapely` が `ImportError: libstdc++.so.6: cannot open shared object file` で失敗しました。
また、nixpkgs 26.05 には Python 3.8 が存在しないため、3.8 での動作検証には uv が取得する Python が不可欠です。
なお、プロジェクトのリポジトリは Nix を使わない同僚とも共有するため、`shell.nix` や `flake.nix` は配置しない方針としています。

### FHS 環境をコマンドとして導入した理由

[packages/uv-mode](../../../packages/uv-mode/default.nix) では buildFHSEnv を使用し、uv や wheel が依存するライブラリ（zlib, libstdc++ など）を FHS 標準のディレクトリ配置に並べた環境を構築しています。
これにより、一般的な Linux 向けバイナリの動作を `uv-mode` 実行内部だけに限定させています。
環境内では `UV_PYTHON_PREFERENCE=only-managed` を設定し、uv が Nix の `python3` を誤って選択しないようにしています。
併せて `IN_UV_MODE=1` を設定し、[dev/uv-mode.nix](../../../modules/home-manager/dev/uv-mode.nix) の Starship 設定（`env_var.IN_UV_MODE`）経由でプロンプトに `uv-mode` と表示させています。これは過去にモード外で `uv sync` を実行し、ビルド用一時環境の Python が起動できず失敗した経験から、モード内にいるかどうかを一目で判別できるようにしたためです。変数名に `UV_` を冠していないのは、uv が `UV_` で始まる環境変数を自身の設定パラメータとして読み込んでしまうのを避けるためで、Nix の `IN_NIX_SHELL` に合わせた命名にしています。
Home Manager 経由で導入しているため、プロジェクト側に固有ファイルを置く必要がなく、`nix develop` のような評価処理も毎回発生しません。導入処理と Starship プロンプト表示は同一モジュール内にまとめて整備しています。
なお、buildFHSEnv は Linux 専用の機能であるため、macOS 上の Home Manager には追加されません。

2026-10-14 に nixos-desktop で実施した検証結果:

- モード内において、uv が取得した Python 3.14.6 に shapely 2.1.2 の wheel を導入して無事インポートできることを確認。また、Python 3.8.20 も取得・起動できることを確認。
- 同環境で作成した venv 内の `python` は、モード外では `Could not start dynamically linked executable` となり起動しないことを確認。
- モード内からでも、ホームディレクトリへの書き込み、名前解決、Home Manager 導入のコマンド（`nvim`、`git` など）は通常通り利用可能。`sudo` のみ `no_new_privs` の制約により失敗することを確認。

同日、nixos-work-wsl（WSL2）環境でも検証を実施しました。モード内では `UV_PYTHON_PREFERENCE` が `only-managed` に適用され、uv が取得した Python 3.14.6 が問題なく起動したことから、WSL2 上でも bubblewrap が正常に動作することが確認できました。

検討のうえ見送った代替案:

- **システム全域で nix-ld を有効化する**: エディタを含めどこからでも `.venv` の Python が動作するようになりますが、uv 以外の配布バイナリまで常に動作してしまいます（[antigravity-cli.md の設計](antigravity-cli.md#設計) で nix-ld を見送った理由と同様）。
- **プロジェクトに `shell.nix` を配置する**: 仕組みとしては同等ですが、共有リポジトリに自分しかメンテナンスできない管理ファイルを残すことになります。
- **direnv で devShell に入る**（[devshells.md](../../architecture/devshells.md) の手法）: direnv は環境変数を読み込むだけであり、buildFHSEnv の名前空間を作り出すことはできません。`mkShell` による devShell には適切なローダーが含まれないため、uv が取得した Python は起動しません。
- **devenv や uv2nix を採用する**: devenv はプロジェクト側に `devenv.nix` を置く前提となります。uv2nix は `uv.lock` から Nix で環境を構築する仕組みであり、Python の取得や venv 構築を uv 自体に任せる運用方針と反することになります。

### トレードオフ・懸念点

- `.venv` 内の Python を呼び出す処理（テスト実行、CLI、エディタの LSP など）は、すべてモード内で起動する必要があります。
- `/etc` はモード用に再構成されるため、`/etc/ssh`、`/etc/nixos`、`/etc/inputrc` などホスト側の一部ファイルが見えなくなります。ただし、nixos-work-wsl の `/etc/ssh` は NixOS のデフォルト設定のみであり、会社の SSH 設定は `~/.ssh/config` に置いているため（[wsl.md](../../architecture/wsl.md) を参照）、Git の接続処理などに影響はありません。
- wheel が提供されずソースからビルドされる依存関係は、モード内のライブラリに対してビルドされるため、モード外では動作しません。

### 未確定事項

- Windows 側の VS Code から WSL に接続して開発を行うかどうか。VS Code Server 自体がバイナリ配布されており nix-ld を必要とするため、その運用を行う場合は nix-ld を有効化し、`uv-mode` は廃止・外す方針となります。
