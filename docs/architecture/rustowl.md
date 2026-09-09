# RustOwl (impure インストール)

設定ファイル: `modules/home-manager/dev/rustowl.nix` の `home.activation.rustowl`

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

1. `dev/rustowl.nix` の `rustowlVersion` を更新
2. `rustowlArchive` の `hash` を更新（ビルド時にハッシュ不一致エラーから正しい値を取得）
3. sysroot バージョン (`SYSROOT` のパス内の Rust バージョン) が変わった場合はそちらも更新

## 注意点

- プロジェクトごとの Rust ツールチェーンは各 devShell の `rust-overlay` が PATH で上書きするため、rustowl の sysroot とは干渉しない
- `home.activation` で実行されるため、`home-manager switch` の度にバージョンチェックが走る（既にインストール済みなら何もしない）

## 対応OS・失敗復旧

使い方と検証: [検証ガイド](../howtouse/validation.md)。
`local.rustowl.enable` はx86_64 Linuxだけで既定true。他のOSではactivation自体を作らず、明示的な有効化はassertionで拒否する。Neovimも実行ファイルが存在するときだけRustOwlプラグインを読み込む。

dry-runではダウンロード・ディレクトリ作成・既存バイナリ実行をしない。通常実行は全工程の最後に `.complete` を書く。途中失敗時にはmarkerが無いので次回switchで再実行する。markerにはNix storeの動的リンカとライブラリパスも含め、世代更新後にrpathを更新する。
既存のNix外インストールは世代ロールバックで戻らない。無効化してもファイルを削除しない。
