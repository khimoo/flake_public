# 規則 A と規則 B の実現（confgen）

規則: [flake_public のあるべき姿](rules.md)
使い方: [confgen.md](../howtouse/confgen.md)

confgen は、[flake_public のあるべき姿](rules.md) の規則 A と規則 B を、`config/elements/*.star` の要素と `config/hosts/*.toml` のホストのファイルで実現する。

部品どうしの関係は、要素の定義の外に宣言しない。以前は `local.relations` に「どの設定がどの目的のためか」を別に宣言していたが、宣言と実際の設定の参照がずれても止まらず、基盤（Neovim）が機能（sshfs）の有無を調べて分岐していた。

## 規則の言葉と confgen の対応

| 規則の言葉 | confgen での書き方 |
|---|---|
| 部品 | 要素。`config/elements/*.star` の1ファイルが要素1つにあたる |
| 公理 | ホストのファイルの `purposes` に挙げた要素の判定。`purposes` には、行動の要素と、機体の要素（`machine_<ホスト>`）を挙げる |
| 前件が1つの推論規則 | 参照。要素 X が要素 Y を参照すると、「要素 X の判定が真ならば、要素 Y の判定も真」になる。参照は、関数の仮引数（受け取る、渡す）と `requires`（値を読まずに使う）で書く |
| 前件が複数の推論規則 | 派生要素の `when`。「`when` に挙げた要素の判定がすべて真ならば、派生要素の判定も真」になる |
| 受け取る | 関数の仮引数で要素 Y を受け、要素 Y の `public` の値を読む |
| 渡す | `writes` の仮引数で要素 Y を受け、要素 Y に値を書き込む。`config` が option（`home.packages` など）に値を出すのも、option への書き込みとして扱う。複数の要素が同じ option に値を出し、NixOS のモジュールの仕組みが値を合わせるのは、渡すにあたる |
| 外から持ち込む部品 | nixpkgs のパッケージと、nixpkgs、Home Manager、flake の入力のモジュール |

参照は要素の定義の中の式で決まり、ホストの `purposes` では変わらない。

派生要素は、どの要素からも参照できず、`purposes` にも挙げられない。派生要素の判定が真になるのを、`when` に挙げた要素がそろったときに限るため。このため、派生要素を後件に持つ推論規則は `when` の1つだけで、派生要素について「または」は書けない。参照される要素は複数の要素から参照できるので、前件が1つの推論規則どうしの「または」は書ける。

## 守らせ方

規則 B は言語と confgen の検査で守る。Nix では守れない。Nix のモジュールは `config` 全体を読め、要素に `pkgs` を渡すとその中の関数でファイルを読めるため。

- Starlark にはファイル、環境変数、時刻を読む手段が無い。confgen は `load` を止め、要素に渡す組み込みの名前を `write`、`struct` と印を作る関数（[使い方](../howtouse/confgen.md)の表）に限る。
- ホストとユーザーの情報（system、ユーザー名、home と、TOML の値）は、confgen が要素 `host` と `user` として渡し、全ホストの TOML は `machines` として渡す。要素がホスト名やフラグで分岐しなくて済むようにするため。
- 仮引数の集合は、使われていない仮引数を止める検査で、本体の式が実際に指す要素と一致させる。
- 仮引数には、confgen が作る要素の値を渡す。Starlark の中では作れないので、`write` の相手は仮引数でしか指せない。この値を公開値や書き込みの値に入れて渡すことは止める。
- 公開値は凍結してから渡す。読んだ側が書き換えて、同じ値を読む別の要素の結果を変えることを防ぐ。
- 評価の順は、`public`（読む相手の `public` が先）、`writes`、`config`（自分への書き込みを受け取る）。`public` は自分への書き込みを受け取れない。

規則 B を保証できるのは `config/elements/` の要素の中だけ。Nix のモジュールとして残っている設定は、合わさった後の値を読めるので保証の外にある。

要素が値を見て設定値をすべて空にする書き方（規則 A に反する）は、confgen の検査では止められない。

## Nix との分担

confgen は Nix の評価の途中で build して実行し（import from derivation）、ホストごとの JSON を作る。手で実行する手順や、生成物の commit をなくすため。[confgen.nix](../../modules/home-manager/confgen.nix) と [NixOS 側](../../modules/nixos/confgen.nix) は JSON をそれぞれの設定にし、印（`$pkg`、`$exe`、`$concat`）をそのホストの `pkgs` の値に置き換える。

値（ホストの構成、`purposes`、ホストとユーザーの値）は TOML に置き、処理は要素に置く。flake は評価の最初に構成の一覧を決める必要があり、Nix が読めるのは Nix、JSON、TOML だけなので、ホストのファイルは TOML にした。flake（`lib/configurations.nix`）は `config/hosts/*.toml` から構成の名前、system、ユーザーを読み、confgen は同じファイルを要素に渡す。同じ値を2か所に書かなくて済む。

ホスト名、system、ユーザー名は、`lib/configurations.nix` が import するときに渡す。`purposes` はホストごとに1つのファイルで選ぶので、同じホストのユーザーは同じ `purposes` を受け取る。`config` や module 引数の `pkgs` から決めると、設定の名前の一覧を決めるのに設定そのものが要り、無限再帰になる。confgen の build には specialArgs の `inputs` の nixpkgs を使う。

この build もほかの build と同じく、`nixos-spin713` ではデスクトップに回る。macOS の Home Manager 構成では aarch64-darwin の confgen を build するので、Linux の `check.sh` からは評価できない。Mac を使い始めるまで、そのホストのファイルを置いていない。

## 変更が影響する範囲

`confgen affected <repo-root> <変更ファイル>...` は1行の JSON `{"elements": [...], "hosts": [...]}` を返す。`elements` は変更した要素、その公開値を読む要素、書き込み先、派生条件にその要素を含む要素。`hosts` は、それらを生成する実在ホストの名前。ホスト・ユーザーの情報を変更した場合は、それぞれ `host`・`machines`・`user` への影響として扱う。要素から影響を辿れない変更は `elements = ["ALL"]` とする。

[scripts/check.sh](../../scripts/check.sh) はこの結果と各 check の札を照合して、ホストの評価とテストのビルドを選ぶ。札と実行範囲は [検証ガイド](../howtouse/validation.md#checksh) を参照。
