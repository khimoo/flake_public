# 共通 devShell の設計方針

使い方は [howtouse/devshells.md](../howtouse/devshells.md) を参照。
ここでは「なぜこの構成にしたか」を記録する。

## 解決したい問題

`~/sagyo/` 配下に複数のコードリーディング対象/実験用リポジトリを抱えており、
それぞれに対して個別に `flake.nix` を書いて Rust toolchain や Python の
科学スタックを揃えるのが煩雑だった。当初の `aquaponics-sim/flake.nix` と
`rust-toybox/flake.nix` は実質同じ Bevy 用 native lib 一式を持っており、
重複が問題だった。

## 採用した解

flake_public に `devShells.x86_64-linux.<name>` として **named devShell** を
集約し、各プロジェクトは `.envrc` で 1 行参照する：

```
use flake "/home/pomu/sagyo/flake_public#rust-bevy"
```

direnv + nix-direnv が `cd` 時に devShell を自動 enter/exit し、ビルド結果は
キャッシュされる。

### 検討した代替案と却下理由

| 案 | 却下理由 |
|----|----------|
| [the-nix-way/dev-templates](https://github.com/the-nix-way/dev-templates) をそのまま使う | Bevy 用の Wayland/Vulkan/alsa/udev 一式と Python 科学スタック (geopandas, scikit-learn 等) が含まれず、結局自前で flake を書くことになる |
| home-manager で LSP をグローバルインストール | rust-analyzer のマクロ展開等で `cargo check` が走る関係で結局 Bevy 系の native lib も system に常駐させる羽目になり、本番 NixOS 設定が肥大化する |
| `devenv.sh` を採用 | 上物が増える。現状 nixpkgs の `mkShell` で足りており、`devenv` 固有の機能 (process-compose, services) を必要としていない |

## shell 粒度の判断基準

- **同じ native lib 集合を要求するプロジェクトはまとめる**: `rust-bevy` は
  Bevy / wgpu / winit / egui 系の native lib を一括で抱える
- **native lib が要らない用途は分ける**: 競プロや上流リポジトリ読みは
  `rust-min` (rustTools + pkg-config のみ) で十分。Vulkan loader 等を引っ張ら
  ないので入域も速い
- **逆に、ほぼ同じだが微妙に違う場合に新 shell を作りすぎない**: project
  固有の追加パッケージは project 側で対応 (例: TypeScript 拡張の
  `npm install`, Python project の `uv venv`)

## Rust toolchain は nixpkgs stable を使う

`rust-overlay` / `fenix` を使わず、`pkgs.rustc` / `pkgs.cargo` /
`pkgs.rust-analyzer` を直接使う。理由:

- 現在 `~/sagyo` 配下に nightly 限定機能 (`#![feature(...)]` 等) を使う
  project が無い (rust-toybox を全 grep して確認済み)
- nightly が要らないなら `rust-overlay` も不要で、flake input が 1 個減って
  lock も軽くなる
- std へのジャンプは `RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}"` で
  実現可能で、`rust-overlay` の `extensions = [ "rust-src" ]` と等価な結果に
  なる

### nightly が要るときは

将来 nightly が必要な project が出てきたら、その時に rust-overlay を
input に再度追加し、`rust-nightly` shell を生やす。`rust-toybox/flake.nix`
の元のコード (削除済み) は git history に残っているので参照可能。

## 例外: 個別 `flake.nix` を残しているケース

| プロジェクト | 残している理由 |
|--------------|----------------|
| `aquaponics-sim/` | 外部公開を予定しており、clone した第三者が再現できる必要があるため自己完結した `flake.nix` を保持 |
| `MDA/.../backend/` | shellHook 内で `uv tool install specify-cli` 等の project 固有のセットアップを行っており、共通 shell に出すと他 project に不要な副作用が出る |

これらは「flake.nix を書くこと自体が project に意味を持つ」ケース。共通化の
対象は **使い捨てのコードリーディング/実験用 project** に限定する。

## rustowl との関係

`modules/home-manager/dev/rustowl.nix` が rustowl を impure に導入している
が、これは devShell とは独立。

- **rustowl**: 借用ライフタイム可視化ツール。専用 nightly sysroot を内部に
  持ち、`~/.local/share/rustowl/sysroot/...` に閉じている。PATH には
  rustowl 本体しか出ない
- **devShell の rustc/cargo/rust-analyzer**: ユーザーが書く Rust コードの
  build/edit 用。PATH に出る

機能が被っているように見えるが、rustowl は borrow 可視化専用、devShell の
rust-analyzer は標準 LSP (定義ジャンプ等) と役割が異なる。両者を併用する
前提。詳細: [rustowl.md](./rustowl.md)。
