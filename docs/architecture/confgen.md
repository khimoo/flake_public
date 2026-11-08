# 目的から設定を生成する規則（confgen）

使い方: [confgen.md](../howtouse/confgen.md)

## 解決したい問題

- 設定を変えるとき、確かめるべき範囲が分からない。
- ある機能のために足した設定が、その機能を外した後も残る。

以前は `local.relations` に「どの設定がどの目的のためか」を別に宣言していたが、宣言と実際の設定の参照がずれても止まらず、基盤（Neovim）が機能（sshfs）の有無を調べて分岐していた。

## 規則

要素は `config/elements/*.star` の1ファイル。ホストが選んだ目的を S とする。

- **存在（A）**: 生成される要素の集合は、次の2つを満たす最小の集合。選んだ目的と、生成される要素が参照する要素は生成される。派生要素は、`when` に挙げた要素がすべて生成されるとき生成される。
- **依存（B）**: 要素 x の結果が別の要素 y で変わるのは、x が y の公開値を読むか、y が x に書き込む場合に限る。
- 派生要素はどの要素からも参照できず、目的として選べない。したがって派生要素は、条件がそろったときに限って生成される。

参照は、関数の仮引数（読む・書き込む）と `requires`（値を読まずに使う）。仮引数の集合は、使われていない仮引数を止める検査で、本体の式が実際に指す要素と一致させる。参照は定義の中の式で決まり、どの目的を選ぶかでは変わらない。

`config` が値を出す option（`home.packages` など）は、その option への書き込みとして扱う。複数の要素が同じ option に値を出し、NixOS のモジュールの仕組みが合わせるのは、B の書き込みにあたる。

## 守らせ方

B は言語と confgen の検査で守る。Nix では守れない。Nix のモジュールは `config` 全体を読め、要素に `pkgs` を渡すとその中の関数でファイルを読めるため。

- Starlark にはファイル、環境変数、時刻を読む手段が無い。confgen は `load` を止め、要素に渡す組み込みの名前を `write`、`struct` と印を作る関数（[使い方](../howtouse/confgen.md)の表）に限る。
- ホストとユーザーの情報（system、ユーザー名、home と、TOML の値）は、confgen が要素 `host` と `user` として渡し、全ホストの TOML は `machines` として渡す。要素がホスト名やフラグで分岐しなくて済むようにするため。
- 仮引数には、confgen が作る要素の値を渡す。Starlark の中では作れないので、`write` の相手は仮引数でしか指せない。この値を公開値や書き込みの値に入れて渡すことは止める。
- 公開値は凍結してから渡す。読んだ側が書き換えて、同じ値を読む別の要素の結果を変えることを防ぐ。
- 評価の順は、`public`（読む相手の `public` が先）、`writes`、`config`（自分への書き込みを受け取る）。`public` は自分への書き込みを受け取れない。

B を保証できるのは `config/elements/` の要素の中だけ。Nix のモジュールとして残っている設定は、合わさった後の値を読めるので保証の外にある。

## Nix との分担

confgen は Nix の評価の途中で build して実行し（import from derivation）、ホストごとの JSON を作る。手で実行する手順や、生成物の commit をなくすため。[confgen.nix](../../modules/home-manager/confgen.nix) と [NixOS 側](../../modules/nixos/confgen.nix) は JSON をそれぞれの設定にし、印（`$pkg`、`$exe`、`$concat`）をそのホストの `pkgs` の値に置き換える。

値（ホストの構成、目的、ホストとユーザーの値）は TOML に置き、処理は要素に置く。flake は評価の最初に構成の一覧を決める必要があり、Nix が読めるのは Nix、JSON、TOML だけなので、ホストのファイルは TOML にした。flake（`lib/configurations.nix`）は `config/hosts/*.toml` から構成の名前、system、ユーザーを読み、confgen は同じファイルを要素に渡す。同じ値を2か所に書かなくて済む。

ホスト名、system、ユーザー名は、`lib/configurations.nix` が import するときに渡す。目的はホストごとに1つのファイルで選ぶので、同じホストのユーザーは同じ目的を受け取る。`config` や module 引数の `pkgs` から決めると、設定の名前の一覧を決めるのに設定そのものが要り、無限再帰になる。confgen の build には specialArgs の `inputs` の nixpkgs を使う。

この build もほかの build と同じく、`nixos-spin713` ではデスクトップに回る。macOS の Home Manager 構成では aarch64-darwin の confgen を build するので、Linux の `check.sh` からは評価できない。Mac を使い始めるまで、そのホストのファイルを置いていない。

## 対象外

- 実行時の依存（Lua やシェルが名前で呼ぶコマンド、環境変数）と、実行時に作られる状態（キャッシュ）。
- nixpkgs や Home Manager のモジュールの中身。
