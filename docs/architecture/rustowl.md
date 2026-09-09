# RustOwl (rustowl-flake 由来)

設定ファイル: [`modules/home-manager/dev/rustowl.nix`](../../modules/home-manager/dev/rustowl.nix)

## 背景

RustOwl は `rustc_private` を使うため専用の nightly sysroot を必要とし、nixpkgs には収録されていない。

以前は GitHub Releases のプリビルドバイナリを `home.activation` で展開し、sysroot を `rustowl toolchain install` で実行時ダウンロードしていた。この方式は switch のたびにネットワークへ出るため、`home-manager-<user>.service` の起動タイムアウト（5分）に当たって switch 全体を失敗させた。sysroot 約568MBのダウンロードが間に合わないため。marker に Nix store のパスを含めていたので、nixpkgs 更新のたびに再ダウンロードが走る構造でもあった。

## 仕組み

flake input `rustowl` は [nix-community/rustowl-flake](https://github.com/nix-community/rustowl-flake)。RustOwl 上流の `docs/installation.md` が案内しているコミュニティ版で、作者公式ではない。

このflakeは `rust-toolchain.toml` に固定された nightly を rust-overlay で用意し、RustOwl をソースからビルドする。`$out/bin/sysroot/<toolchain>` に toolchain を配置するため、RustOwl の sysroot 探索がstore内で完結し、実行時ダウンロードへフォールバックしない。

`modules/home-manager/dev/rustowl.nix` は次の2つだけを行う。activation は無い。

1. `home.packages` に `rustowl` を追加
2. `xdg.dataFile."nvim/nix/rustowl.lua"` に、実行ファイルとNeovimプラグインのstore pathを書き出す

## Neovim 連携

`lua/plugins/lang/rust.lua` は上記のブリッジファイルを `dofile` で読み、lazy.nvim には `dir` でstore内のプラグインを指す。LSPの起動コマンドも絶対store pathで渡す。

- サーバとプラグインが同じflakeから来るため、両者のバージョンが常に一致する
- 絶対pathを使うので、旧方式が残した `~/.local/bin/rustowl` がPATHで優先されても影響しない
- `local.rustowl.enable` が false のときブリッジは `return nil` を返し、プラグインと対応キーを読み込まない
- プラグイン実体はNixが持つので `lazy-lock.json` には載せない

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

`local.rustowl.enable` は x86_64 Linux だけで既定 true。他のOSでは `home.packages` に何も足さず、明示的な有効化は assertion で拒否する。

検証の範囲: [検証ガイド](../howtouse/validation.md)。
