# RustOwl (rustowl-flake 由来)

設定ファイル: [`config/elements/nvim_rustowl.star`](../../config/elements/nvim_rustowl.star)、[`overlays/neovim-tools.nix`](../../overlays/neovim-tools.nix)

## 背景

RustOwl は `rustc_private` を使うため専用の nightly sysroot を必要とし、nixpkgs には収録されていない。

GitHub Releases のビルド済みバイナリを `home.activation` で展開し、sysroot を `rustowl toolchain install` で実行時に取得する方式は退けた。switch のたびにネットワークへ出て、sysroot（約 568MB）の取得が `home-manager-<user>.service` の起動のタイムアウト（5 分）に間に合わず、switch 全体を失敗させた。marker に Nix store のパスを含めていたので、nixpkgs を更新するたびに取得し直す作りでもあった。

## 仕組み

flake input `rustowl` は [nix-community/rustowl-flake](https://github.com/nix-community/rustowl-flake)。RustOwl 上流の `docs/installation.md` が案内しているコミュニティ版で、作者公式ではない。

このflakeは `rust-toolchain.toml` に固定された nightly を rust-overlay で用意し、RustOwl をソースからビルドする。`$out/bin/sysroot/<toolchain>` に toolchain を配置するため、RustOwl の sysroot 探索がstore内で完結し、実行時ダウンロードへフォールバックしない。

[flake.nix](../../flake.nix) は x86_64 Linux の `packages.${system}` に `rustowl` と `rustowl-nvim` を、同じ locked input の `inputs.rustowl.packages.${system}` から組で公開する。`overlays/neovim-tools.nix` は同じ input から `rustowl-locked` と `rustowl-nvim-locked` を pkgs に入れる。要素 `nvim_rustowl` は、サーバーを rustowl 機能の `data.command` に、対応するプラグインを同機能の `data.plugin` に書き込む（`nvim/nix/features.lua` の `data.rustowl` に生成）。activation は無い。

LSP サーバーと同じく、`rustowl` はシェルの PATH に入れない。シェルから使うときは `nix run .#rustowl -- <引数>` で、同じ版を実行する。

## Neovim 連携

`lua/features/rustowl.lua` は `require("config.nix").data.rustowl` を読み、lazy.nvim には `dir` でstore内のプラグインを指す。LSPの起動コマンドも絶対store pathで渡す。

- サーバとプラグインが同じflakeから来るため、両者のバージョンが常に一致する
- 絶対pathを使うので、旧方式が残した `~/.local/bin/rustowl` がPATHで優先されても影響しない
- x86_64 Linux 以外では rustowl 機能を書き込まないので、プラグインと対応キーを読み込まない
- プラグイン実体はNixが持つので `lazy-lock.json` には載せない

キーと操作は [Neovim の Rust 言語サポート](../howtouse/neovim/lang-rust.md) を参照。

## バージョン更新手順

```sh
nix flake update rustowl
```

rustowl-flake は上流の `main` を追うため、パッケージの `version` は `<cargo version>-unstable` になる。実際に固定されるRustOwlのrevisionは `flake.lock` を見る。

## 注意点

- プロジェクトごとの Rust ツールチェーンは各 devShell の `rust-overlay` が PATH で上書きするため、RustOwl の sysroot とは干渉しない
- 旧方式が残した `~/.local/share/rustowl`（sysroot 実体）と `~/.local/bin/rustowl` はNix管理外であり、自動削除されない。不要なら手動で消す
- flake input として `rust-overlay` と `flake-parts` などが間接的に増える。ビルドはnix-community の cachix に載っているが、本リポジトリの nixpkgs で overlay を適用した場合はローカルビルドになりうる

## 対応OS

要素 `nvim_rustowl` は、confgen が渡すホストの情報（`host.system`）が x86_64-linux のときだけ機能を書き込む。他の OS では overlay のパッケージを参照しないので、rustowl-flake の配布の無い macOS でも評価できる。

検証の範囲: [検証ガイド](../howtouse/validation.md)。
