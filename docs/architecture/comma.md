# comma と nix-index-database

[howtouse/cli-tools/comma.md](../howtouse/cli-tools/comma.md) の設計判断。
実装は [modules/home-manager/nix-index.nix](../../modules/home-manager/nix-index.nix)。

## 配布済みのデータベースを使う

comma と nix-index の command-not-found ハンドラは、ファイル名からパッケージを引く nix-index のデータベースを使う。
`nix-index` を手元で実行すると、nixpkgs の全パッケージのファイル一覧を binary cache から取り寄せて索引を作る。spin713 のような非力なマシンでこれを定期的に走らせたくない。
nix-index-database は nixos-unstable の索引を週に一度作り、GitHub Releases に置く。flake input で版を固定し、データベースは `fetchurl` の hash で固定されるので、switch のたびに取り直すことはない。

Home Manager のモジュール（`homeModules.nix-index`）を使う。NixOS のモジュールでは、standalone の Home Manager を使う WSL と macOS に入らない。

手元で `nix-index` を定期実行する案は退けた。固定した nixpkgs と索引の版を揃えられるが、索引作りの負荷がノートにかかる。

## small データベースで両方を動かす

upstream は2種類のデータベースを配布する。2026-09-20 のリリース（`2026-09-20-075601`）の実測で、x86_64-linux の full は 101MiB、small は 1MiB、aarch64-darwin の full は 64MiB、small は 1MiB だった。
small は各パッケージの `bin/` 配下のファイルだけを収録する。
upstream の既定では comma が small を、nix-index（command-not-found ハンドラと `nix-locate`）が full を使う。

comma も command-not-found ハンドラも、実行ファイル名からパッケージを引くだけなので small で足りる。
full を使うと、`nix-index-database` を更新するたびに約100MiB が store に増え、古い世代が参照している間は GC で消えない。
そこで `programs.nix-index.package` を `nix-index-with-small-db` に差し替えた。

upstream のモジュールは、`programs.nix-index.package` とは別に、`programs.nix-index.enable` が真なら full のデータベースを `~/.cache/nix-index/files` へ symlink する（`symlinkToCacheHome`）。
comma と `nix-locate` のラッパーはどちらも `NIX_INDEX_DATABASE` でデータベースを指定するので、この symlink を読まない（nix-index-database の rev `9ad7226` の `comma-wrapper.nix` と `nix-index-wrapper.nix`）。
`symlinkToCacheHome = false` にして、full のデータベースを取得しないようにした。

代償として、`lib/` や `include/` にあるライブラリやヘッダの所属パッケージを `nix-locate` で引けない。

## データベースと nixpkgs の版のずれ

データベースは nixos-unstable を索引しているが、この flake の nixpkgs は nixos-26.05 に固定している。
comma はレジストリの `nixpkgs` からパッケージを取る。NixOS では `nixpkgs.flake.setFlakeRegistry` が真（spin713 で確認）なので、システムの nixpkgs を指す。
そのため、unstable にだけあるパッケージは見つかっても `nix shell` で失敗し、26.05 と unstable で名前が違うパッケージは見つからないことがある。

## 見直す条件

- nix-index-database が stable チャンネルの索引を配布したら、それに切り替えて版のずれをなくす。
- ライブラリやヘッダの所属を `nix-locate` で引く用途が増えたら、`programs.nix-index.package` だけを full に戻す。store の増加と引き換えになる。
- nix-index-database は x86_64-linux、aarch64-linux、aarch64-darwin だけに配布している（rev `9ad7226` の `flake.nix`）。それ以外のプラットフォームの Home Manager 環境を足すときは、このモジュールをそのプラットフォームで無効にする。
