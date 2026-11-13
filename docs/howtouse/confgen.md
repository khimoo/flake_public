# 利用者が選ぶ行動ごとの設定（confgen）

規則: [flake_public のあるべき姿](../architecture/rules.md)
設計: [confgen.md](../architecture/confgen.md)
実装: [config/](../../config/)（要素、ホスト、ユーザー）/ [tools/confgen](../../tools/confgen/)（評価と検査）/ [NixOS への反映](../../modules/nixos/confgen.nix) / [Home Manager への反映](../../modules/home-manager/confgen.nix)

`config/elements/` の Starlark のファイルが、設定の要素を1つずつ定義します。ホストのファイル `config/hosts/<ホスト名>.toml`（standalone の Home Manager では `<構成名>.toml`）は、機体の要素を `machine` で選び、利用者ごとに行動の要素を `[[users]]` の `purposes` で選びます。利用者ごとに、機体と行動から参照をたどれる要素と、条件がそろった派生要素が、その利用者について入る要素になります。switch の評価の途中で confgen が動くので、手で実行する手順はありません。

値は TOML に、処理は要素に書きます。ホストの値は `config/hosts/<ホスト名>.toml`、ユーザーの値は `config/users/<ユーザー名>.toml` に置きます。

## 行動を選ぶ・外す

ホストのファイルの `[[users]]` の `purposes` に、行動の要素の名前を足すか消します。

```toml
machine = "machine_nixos_spin713"

[[users]]
name = "pomu"
purposes = ["programming", "read_materials"]
```

行動を外すと、その利用者について、その行動からしか導けない要素と、その行動を条件に持つ派生要素が外れます。外れた要素の Home Manager の設定はその利用者から消えます。ほかの利用者について入っている要素の NixOS の設定は残ります。

`category_` で始まる要素は分類（勉強、生活管理、趣味、仕事）です。分類は、配下の行動と、分類の行動に共通の道具を `requires` に挙げます。`purposes` に分類を書くと、配下の行動がすべて入ります。分類の一部の行動だけが要る利用者は、行動を個別に書きます。分類の `requires` に直接書いた道具（`task_management` など）は、行動を個別に書く利用者には入りません。

`purposes = []` の利用者には、機体から導ける要素だけが入ります。`purposes` は利用者ごとに必ず書きます。

## ホストとユーザーの値

ホストのファイルの次のキーは、flake が構成を作るときに読みます。

| キー | 中身 |
|---|---|
| `system` | `x86_64-linux` など |
| `kind` | `nixos`（NixOS の構成）か `home`（standalone の Home Manager）。無いファイルは構成を作らず、tests の架空のホストにだけ使う |
| `state_version`、`timezone` | NixOS と Home Manager の stateVersion、タイムゾーン |
| `machine` | 機体の要素の名前。省くと、利用者の `purposes` だけから要素が決まる（tests の架空のホスト） |
| `[[users]]` | `name`、`purposes`、`admin`、`home_manager = false`（Home Manager を使わない人）、`initial_hashed_password` |

`machine` と `purposes` 以外のキーは、要素が仮引数 `host` で読めます（`host.echo_cancel_source`）。全ホストのファイルは仮引数 `machines` で読めます（`machines.all["nixos-desktop"].ssh_user`）。ホストの間の SSH とリモートビルドがこれを使います。`host.users` と `machines` からは `purposes` と `machine` を外してあり、要素はどの要素が入っているかを値として読めません。

ユーザーのファイルのキーと、ホストのファイルの `[[users]]` の `name` と `purposes` 以外のキーは、仮引数 `user` で読めます（`user.git_username`）。同じキーを両方に書くとエラーになります。

## 要素を書く

1つのファイルが1つの要素です。ファイル名が要素の名前です。書けるのは次の6つと、`_` で始まる補助の名前だけです。

| 名前 | 中身 |
|---|---|
| `requires = [...]` | 値を読まずに使う要素（行動が使う道具など） |
| `def public(...)` | 他の要素が読める値の辞書を返す |
| `def writes(...)` | `write(相手, 値)` のリストを返す |
| `def config(..., incoming)` | ホスト全体の設定。`{"nixos": {"option.path": 値}, "nixos_imports": [...]}` を返す。`incoming` は自分への書き込みの一覧（`w.source`、`w.value`） |
| `def user_config(..., incoming)` | 利用者ごとの設定。要素が入る利用者ごとに呼ばれ、`{"home": {...}, "home_imports": [...], "nixos": {...}}` を返す。`nixos` には、その利用者だけの NixOS の設定（`("users", "users", user.name, "extraGroups")` など）を書く |
| `when = [...]` | 派生要素の条件。同じ利用者について、挙げた要素がすべて入るときだけ、この要素が入る |

`config` は、利用者によって変わる値を読めません。利用者によって変わる値は、`user` と、`public` が利用者によって変わる値を読む要素の公開値です（`checkout.root` など）。`public` と `writes` は、利用者によって変わる値を読むと利用者ごとに呼ばれ、読まなければホストごとに1回呼ばれます。

関数の仮引数の名前が、参照する要素の名前です。仮引数には相手の公開値が属性として渡ります（`util_linux.findmnt`）。`write` の第1引数には、`writes` の仮引数の名前をそのまま書きます。

仮引数 `host`、`user`、`machines` は confgen が渡す要素で、要素のファイルはありません。ファイルの値のほかに、`host.system`、`host.linux`、`host.darwin` と、`user.name`、`user.home` を読めます。

option のパスに `.` を含む名前があるときは、タプルで書きます（`("xdg", "dataFile", "nvim/nix/features.lua", "text")`）。外部の flake の Home Manager モジュールが要るときは、`user_config` が `"home_imports": [module("memex-nix", "homeModules.memex")]` を返します。NixOS のモジュールは `config` が `"nixos_imports"` で返します。

機体の性質で入るかどうかが変わる要素は、性質を表す要素を `when` に挙げます。例: [user_repo_packages.star](../../config/elements/user_repo_packages.star) は `when = ["user_packages", "x86_64_linux"]` で、`x86_64_linux` は x86_64 の Linux の機体の要素が `requires` に挙げます。値を見て設定を空にする書き方は、次の節のとおり止められます。

書いた値を confgen の外（Lua やシェルスクリプト）が読み、その読み手が別の要素で有効になるときは、confgen はその依存を見つけられません。読み手を有効にする要素を `requires` に書くか、両方がそろうときだけ入る派生要素（`when`）に分けます。例: [tinymist_on_sshfs.star](../../config/elements/tinymist_on_sshfs.star) は `nvim_lsp` が有効にする Lua が読む値を書くので、`when = ["sshfs_editing", "nvim_lsp"]` にしています。

Nix にしか作れない値は印で書きます。

| 印 | 値 |
|---|---|
| `pkg("sshfs")`、`pkg("vimPlugins.lazy-nvim")`、`inputPkg("input", "attr")` | パッケージ |
| `repoPkg("packages/x")`、`repoPkgWith("packages/x", {...})` | repo の中のパッケージ（`callPackage`） |
| `exe("util-linux", "findmnt")` | パッケージの中のコマンドのパス |
| `concat("前", exe(...), "後")` | 印を含む文字列 |
| `file(name, text)`、`script(name, text)`、`scriptBin(name, text)`、`command(name, script)` | `writeText`、`writeShellScript`、`writeShellScriptBin`、`runCommand` |
| `shellApp(name, runtimeInputs, text)`、`shellAppEnv(...)` | `writeShellApplication` |
| `symlinkJoin(name, paths)`、`pythonWithModules([...])`、`pkgWithPackages(...)`、`pkgSetFn(...)` | パッケージを組み合わせたもの |
| `repoPath("x")`、`repoText("x")`、`flakeRev()` | repo の中のファイルの store のパス、中身、flake のリビジョン |
| `outOfStoreLink(path)` | store の外への symlink（checkout は `checkout.root` から作る） |
| `activation(after, text)`、`mkAfter(v)`、`mkBefore(v)`、`gvariantTuple([...])`、`toJSON(v)` | Home Manager の activation、リストの順序、dconf のタプル、JSON の文字列 |
| `luaPackages(["lpeg"])`、`lua(値)` | Neovim の Lua のパッケージを選ぶ関数、値を Lua の式にした文字列 |
| `module("input", "homeModules.x")`、`repoModule("hosts/x/hardware.nix")` | Nix のモジュール（`home_imports` / `nixos_imports` に入れる） |

`str()` や `%` で印を文字列にすると、confgen がエラーにします。

## 止められる書き方

次の書き方は、評価の途中で confgen がファイル名と行を示して止めます。

- 仮引数に挙げていない要素を使う、使わない仮引数を書く
- 派生要素を仮引数か `requires` で挙げる、`purposes` か `machine` に書く
- 受け取った要素を公開値や書き込みの値に入れて渡す
- 公開値を書き換える（`append` など）
- `load` を書く
- `config` が利用者によって変わる値を読む、`config` が `home` を返す
- 要素が入っているのに、`config` と `writes` が何も返さない（ホストごと）、`user_config` と `writes` が何も返さない（利用者ごと）。`return {}` や `return []` で設定を出さない書き方がこれにあたる
- 利用者ごとに呼ばれる `writes` が、`user_config` を持たない要素に書き込む
- ホストのファイルの先頭に `purposes` を書く、`[[users]]` に `purposes` を書かない

## 変更の範囲を見る

ある要素を変えたときに影響する要素を表示します。

```sh
cd tools/confgen
nix shell nixpkgs#go -c go run . explain ../../config nixos-spin713 x86_64-linux util_linux
```

その要素を読む要素、書き込む要素、条件に持つ派生要素と、その要素が値を出す option を表示します。

ある要素がなぜ利用者について入っているかを、公理（機体か `purposes`）までたどって表示します。行動を外しても残る要素は、ほかの行動からの経路が表示されます。

```sh
nix shell nixpkgs#go -c go run . why ../../config nixos-spin713 x86_64-linux pomu util_linux
```

## 検査

confgen の build がテスト（[confgen_test.go](../../tools/confgen/confgen_test.go)）を実行します。規則に反する書き方を止めること、利用者ごとに自分の行動から導ける要素だけが入ること、派生要素が同じ利用者について条件のそろったときだけ入ることを確かめます。switch の評価はこの build を通るので、テストが失敗すると switch できません。

check `elements-alone`（[tests/elements/confgen.nix](../../tests/elements/confgen.nix)）は `confgen alone` を実行し、どの要素も、ホストの最初の利用者がそれ1つだけを選んだときに生成できることを確かめます。ホストの値と機体は、その要素を生成している既存のホストのものを使います。上の依存を書き忘れた要素はここで止まります。2つの要素が同じ値に書いて衝突する場合は見つけられません。

`nixos-spin713` は手元で build しないので、デスクトップが止まっているときは `--max-jobs 1` を付けて switch します（[remote-build.md](./remote-build.md)）。
