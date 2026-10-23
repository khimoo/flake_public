# 共通 devShell の設計

使い方: [共通 devShell](../howtouse/devshells.md)
実装: [devShells/default.nix](../../devShells/default.nix)

`~/sagyo` の読むだけのリポジトリや実験用のリポジトリごとに `flake.nix` を書いて、Rust の toolchain や Python の科学計算の依存を揃えるのは手間がかかる。`aquaponics-sim` と `rust-toybox` の `flake.nix` は、同じ Bevy 用のライブラリを持っていた。
そこで flake_public に名前付きの devShell を集め、各プロジェクトは `.envrc` の `use flake "/home/pomu/sagyo/flake_public#rust-bevy"` で参照する。

退けた案と理由:

- [the-nix-way/dev-templates](https://github.com/the-nix-way/dev-templates): Bevy 用の Wayland、Vulkan、alsa、udev と、Python の科学計算（geopandas、scikit-learn）が入っておらず、結局自分で書くことになる
- home-manager で LSP を全体に入れる: rust-analyzer のマクロ展開で `cargo check` が実行されるので、Bevy のライブラリもシステムに常に置くことになり、NixOS の設定が膨らむ
- devenv.sh: 層が増える。`mkShell` で足りていて、devenv の機能（process-compose、services）は使わない

## devShell の分け方

- 同じライブラリの集合を要るプロジェクトはまとめる（`rust-bevy`）
- ライブラリが要らない用途は分ける。`rust-min` は Vulkan などを持たないので、入るのも速い
- ほぼ同じで少しだけ違う場合に新しい devShell を作らず、プロジェクトの側で足す（TypeScript の `npm install`、Python の `uv venv`）

## Rust は nixpkgs の stable を使う

rust-overlay や fenix を使わず、`pkgs.rustc`、`pkgs.cargo`、`pkgs.rust-analyzer` を使う。
`~/sagyo` に nightly の機能（`#![feature(...)]`）を使うプロジェクトがなく（rust-toybox を grep して確認）、nightly が要らなければ flake の input を 1 つ減らせる。
std の定義へ飛ぶのは、`RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}"` で rust-overlay の `rust-src` と同じことができる。
nightly が要るプロジェクトが出たら、rust-overlay を input に戻して `rust-nightly` の devShell を足す。`rust-toybox/flake.nix` にあった元のコードは git の履歴にある。

## 自分の `flake.nix` を残すプロジェクト

- `aquaponics-sim/`: 公開する予定で、clone した人が再現できるよう自分の `flake.nix` を持つ
- `MDA/.../backend/`: shellHook で `uv tool install specify-cli` のようなプロジェクト固有の準備をするので、共通にすると他のプロジェクトに要らない副作用が出る

共通にするのは、使い捨ての読むためや実験のためのプロジェクトに限る。

rustowl（[rustowl.md](./rustowl.md)）は devShell とは別で、借用の可視化のための専用の nightly の sysroot をパッケージの中に持ち、Neovim が store の絶対パスで起動する。devShell の rust-analyzer は定義へのジャンプなどの通常の LSP で、両方を使う。
