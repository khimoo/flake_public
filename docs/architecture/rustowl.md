# RustOwl (rustowl-flake 由来)

設定ファイル: [`modules/home-manager/dev/rustowl.nix`](../../modules/home-manager/dev/neovim/rustowl.nix)

## 背景

RustOwl は `rustc_private` を使うため専用の nightly sysroot を必要とし、nixpkgs には収録されていない。

GitHub Releases のビルド済みバイナリを `home.activation` で展開し、sysroot を `rustowl toolchain install` で実行時に取得する方式は退けた。switch のたびにネットワークへ出て、sysroot（約 568MB）の取得が `home-manager-<user>.service` の起動のタイムアウト（5 分）に間に合わず、switch 全体を失敗させた。marker に Nix store のパスを含めていたので、nixpkgs を更新するたびに取得し直す作りでもあった。

## 仕組み

flake input `rustowl` は [nix-community/rustowl-flake](https://github.com/nix-community/rustowl-flake)。RustOwl 上流の `docs/installation.md` が案内しているコミュニティ版で、作者公式ではない。

このflakeは `rust-toolchain.toml` に固定された nightly を rust-overlay で用意し、RustOwl をソースからビルドする。`$out/bin/sysroot/<toolchain>` に toolchain を配置するため、RustOwl の sysroot 探索がstore内で完結し、実行時ダウンロードへフォールバックしない。

[flake.nix](../../flake.nix) は x86_64 Linux の `packages.${system}` に `rustowl` と `rustowl-nvim` を、同じ locked input の `inputs.rustowl.packages.${system}` から組で公開する。Home Manager は `inputs.self.packages.${system}` を参照し、公開側と同じサーバーを rustowl 機能の `data.command` に、対応するプラグインを同機能の `data.plugin` に使う。公開属性を削除して導入参照が残ると評価エラーになる。

`modules/home-manager/dev/rustowl.nix` は、`local.neovim.features.rustowl` に実行ファイルとNeovimプラグインの store path を定義するだけを行う（`nvim/nix/features.lua` の `data.rustowl` に生成）。activation は無い。

LSP サーバーと同じく、`rustowl` はシェルの PATH に入れない。シェルから使うときは `nix run .#rustowl -- <引数>` で、同じ版を実行する。

## Neovim 連携

`lua/features/rustowl.lua` は `require("config.nix").data.rustowl` を読み、lazy.nvim には `dir` でstore内のプラグインを指す。LSPの起動コマンドも絶対store pathで渡す。

- サーバとプラグインが同じflakeから来るため、両者のバージョンが常に一致する
- 絶対pathを使うので、旧方式が残した `~/.local/bin/rustowl` がPATHで優先されても影響しない
- `local.rustowl.enable` が false のとき rustowl 機能も無効になり、プラグインと対応キーを読み込まない
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

`local.rustowl.enable` は x86_64 Linux だけで既定 true。明示的な有効化は他のOSでは assertion で拒否する。
無効時は公開パッケージを評価せず、rustowl 機能を読み込まないため、公開属性のない macOS でも評価できる。

検証の範囲: [検証ガイド](../howtouse/validation.md)。
