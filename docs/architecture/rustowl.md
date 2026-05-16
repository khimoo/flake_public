# RustOwl (impure インストール)

設定ファイル: `modules/home-manager/dev.nix` の `home.activation.rustowl`

## 背景

RustOwl は特定の nightly Rust sysroot を必要とし、nixpkgs でのパッケージングが困難。
Nix store 外に命令的にインストールする impure な要素。

## 仕組み

1. GitHub Releases のプリビルドバイナリ（`fetchurl` で固定ハッシュ取得）を `~/.local/share/rustowl/` に展開
2. `rustowl toolchain install` で sysroot をランタイムダウンロード
3. NixOS の動的リンカパスが標準 Linux と異なるため、`patchelf` で以下を修正:
   - rustowl 本体
   - sysroot 内の ELF バイナリ (`rustowlc`, `rustc`, `rustdoc`, `cargo` 等)
   - sysroot の共有ライブラリ (`librustc_driver` が `libz` 等を必要とする)
4. `~/.local/bin/rustowl` にシンボリックリンクを作成

## バージョン更新手順

1. `dev.nix` の `rustowlVersion` を更新
2. `rustowlArchive` の `hash` を更新（ビルド時にハッシュ不一致エラーから正しい値を取得）
3. sysroot バージョン (`SYSROOT` のパス内の Rust バージョン) が変わった場合はそちらも更新

## 注意点

- プロジェクトごとの Rust ツールチェーンは各 devShell の `rust-overlay` が PATH で上書きするため、rustowl の sysroot とは干渉しない
- `home.activation` で実行されるため、`home-manager switch` の度にバージョンチェックが走る（既にインストール済みなら何もしない）
