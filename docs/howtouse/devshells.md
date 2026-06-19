# 共通 devShell の使い方

`~/sagyo` 配下の各プロジェクトから `.envrc` 経由で参照する共通 devShell 群。
コードリーディング・小さな実験のために、毎回 `flake.nix` を書かずに済ませる
ためのもの。設計判断は [architecture/devshells.md](../architecture/devshells.md)。

## 提供している devShell

| 名前 | 用途 | 主な中身 |
|------|------|----------|
| `rust-bevy` | Bevy / wgpu / winit / egui を含む Rust | nixpkgs stable Rust + Wayland/Vulkan/X11/alsa/udev 一式 |
| `rust-min` | 競プロ・上流リポジトリの読みなど GUI lib 不要な Rust | nixpkgs stable Rust + pkg-config |
| `py-sci` | FastAPI / scikit-learn / geopandas など科学・地理 Python | python3.12 + scipy/pandas/sklearn/geopandas + GDAL/GEOS/PROJ + pyright/uv/just |
| `ts-web` | ブラウザ拡張・SPA など TypeScript | nodejs_22 + pnpm/yarn + tsserver + prettier/eslint |

Rust 系はいずれも `RUST_SRC_PATH` を `rustPlatform.rustLibSrc` に設定済みなので、
rust-analyzer で std へのジャンプが効く。nightly が必要になったら
[architecture/devshells.md](../architecture/devshells.md) の "nightly が要るときは"
節を参照。

実体: [`devShells/default.nix`](../../devShells/default.nix)

## 使い方

対象リポジトリで `.envrc` を作って `direnv allow` するだけ。

```sh
cd ~/sagyo/<repo>
echo 'use flake "/home/pomu/sagyo/flake_public#rust-bevy"' > .envrc
direnv allow
```

`cd` で自動的に devShell に入り、`cd` で離れると自動的に抜ける。
ビルド結果は nix-direnv がキャッシュするので、二回目以降は瞬時。

### 上流リポジトリ (bevy 等) — リポジトリを汚さずに使う

upstream をクローンしただけのリポジトリには `.envrc` を commit したくないので、
リポジトリ単位の exclude にパターンを追加してから配置する：

```sh
cd ~/sagyo/<upstream-repo>
echo '.envrc'   >> .git/info/exclude
echo '.direnv/' >> .git/info/exclude
echo 'use flake "/home/pomu/sagyo/flake_public#rust-bevy"' > .envrc
direnv allow
```

全リポジトリで一律に無視したい場合は `~/.config/git/ignore` に書いておく方が
楽だが、これは現状 home-manager 管理にしていないので各自で。

## トラブルシューティング

- `direnv: error use_flake ...`: `direnv allow` し忘れか、flake_public 側の
  `flake.lock` が壊れている。`nix flake show /home/pomu/sagyo/flake_public`
  で評価が通るか確認。
- LSP が project の依存を見つけない (Rust): `cargo check` を一度走らせる
  必要がある。Bevy 系は初回 `cargo check` が長い。
- LSP が project の依存を見つけない (Python): `py-sci` は科学スタックを
  グローバルに含むが、project 固有の依存は project 側で `uv venv` + `uv pip
  install` 等で揃える。`pyright` は `pyrightconfig.json` の
  `venvPath`/`venv` を読む。

## 別の devShell を増やしたいとき

[`devShells/default.nix`](../../devShells/default.nix) に attribute を追加する。
追加後は `nix flake show /home/pomu/sagyo/flake_public` で attribute が
増えていることを確認し、`.envrc` から参照する。

設計指針 (どの粒度で shell を切るか) は
[architecture/devshells.md](../architecture/devshells.md) を参照。
