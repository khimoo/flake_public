# comma

インストールしていないコマンドを、先頭に `,` を付けて一度だけ実行する。
Home Manager を使う全環境に入る。設定は [modules/home-manager/nix-index.nix](../../../modules/home-manager/nix-index.nix)。
設計判断は [architecture/comma.md](../../architecture/comma.md)。

## 実行する

```bash
, cowsay hello   # cowsay を含むパッケージを探し、nix shell 経由で実行する
, -s cowsay      # そのパッケージを入れたシェルに入る
, -p cowsay      # 実行せず、該当するパッケージを表示する
```

候補が複数あるときは fzy で選ぶ。選んだ結果は保存され、次からは聞かれない。選び直すときは `-d` を付けて実行する。

`-i` はパッケージを `nix profile` に入れる。Home Manager の管理の外に入るので、常用するコマンドは Nix の設定に書く。

パッケージはレジストリの `nixpkgs` から取る。
NixOS では `nixpkgs.flake.setFlakeRegistry` によってシステムの nixpkgs（この flake が固定した nixos-25.11）を指す。
システムのレジストリに `nixpkgs` がない環境では、グローバルレジストリの nixpkgs-unstable になる。`-F` で別の flake を指定できる。

## 未知のコマンドを打ったとき

bash の command-not-found ハンドラが、そのコマンドを含むパッケージを表示する。実行はしない。標準出力が端末でないとき（パイプの途中など）は `command not found` だけを出す。

```text
$ cowsay
The program 'cowsay' is currently not installed. It is provided by
several packages. You can install it by typing one of the following:
  nix-env -iA nixpkgs.neo-cowsay.out
  nix-env -iA nixpkgs.cowsay.out
...
```

表示される `nix-env -iA` は Home Manager の管理の外に入れるので使わない。一度だけ使うなら `, cowsay` で実行する。

## nix-locate

`nix-locate` も comma と同じデータベースを引く。

```bash
nix-locate --whole-name --at-root /bin/rg
```

データベースは各パッケージの `bin/` 配下のファイルだけを収録している。`lib/` や `include/` にあるライブラリやヘッダからは引けない。

## データベースを更新する

```bash
nix flake update nix-index-database
```

nix-index-database は週に一度データベースを作り直す。`flake.lock` を上げて switch するまで、手元のデータベースは固定した版のままになる。

データベースは nixos-unstable を索引している。レジストリの `nixpkgs` が nixos-25.11 を指す環境では、unstable にだけあるパッケージが見つかっても `nix shell` で失敗し、名前が変わったパッケージは見つからないことがある。
