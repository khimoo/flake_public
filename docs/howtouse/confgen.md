# 利用者が選ぶ行動ごとの設定（confgen）

規則: [flake_public のあるべき姿](../architecture/rules.md)
設計: [confgen.md](../architecture/confgen.md)
実装: [config/](../../config/)（要素、ホスト、ユーザー）/ [tools/confgen](../../tools/confgen/)（評価と検査）/ [NixOS への反映](../../modules/nixos/confgen.nix) / [Home Manager への反映](../../modules/home-manager/confgen.nix)

`config/elements/` の Starlark のファイルが、設定の要素を1つずつ定義します。ホストのファイル `config/hosts/<ホスト名>.toml`（standalone の Home Manager では `<構成名>.toml`）は、機体の要素を `machine` で選び、利用者ごとに行動の要素を `[[users]]` の `purposes` で選びます。利用者ごとに、機体と行動から参照をたどれる要素と、条件がそろった派生要素が、その利用者について入る要素になります。switch の評価の途中で confgen が動くので、手で実行する手順はありません。

値は TOML に、処理は要素に書きます。ホストと利用者の値は `config/hosts/<ホスト名>.toml`、リポジトリの持ち主の値は `config/owner.toml` に置きます。

## 行動を選ぶ・外す

ホストのファイルの `[[users]]` の `purposes` に、行動の要素の名前を足すか消します。

```toml
machine = "machine_nixos_spin713"

[[users]]
name = "pomu"
purposes = ["programming", "read_materials"]
```

行動を外すと、その利用者について、その行動からしか導けない要素と、その行動を条件に持つ派生要素が外れます。外れた要素の Home Manager の設定はその利用者から消えます。ほかの利用者について入っている要素の NixOS の設定は残ります。

`purposes = []` の利用者には、機体から導ける要素だけが入ります。`purposes` は利用者ごとに必ず書きます。

## 機体の事実

機体によって入るかどうかが変わる要素は、機体の名前ではなく、機体の事実を条件にします。

- 機体の要素（`kind = "machine"`）は、ホストのファイルの `machine` にだけ書けます。ほかの要素の `requires` や `when` には書けません。
- 機体の事実（`kind = "machine_fact"`）は、設定では用意できない機体の性質です。例: `x86_64_linux`、`nixos_system`（confgen が NixOS の設定を作る）、`rocm_compute`（ROCm で GPU の計算ができる）、`local_kvm`（KVM の仮想マシンを動かせる）。

機体の事実は、機体の要素の `requires` にだけ書けます。行動や道具の `requires` に書くと止まります。行動を選んだだけで「KVM を動かせる」が真になってしまうからです。

機体によって変わる要素は、派生要素の `when` に行動と事実を書きます。

```python
# mimikopi_for_music.star
when = ["make_music", "rocm_compute"]
requires = ["mimikopi"]
```

新しい機体を足すときは、機体の要素の `requires` に、その機体の事実を書くだけです。行動と派生要素は変えません。

`needs = [...]` は、判定が済んだ後の検査で、要素を有効にはしません。要素が入る利用者について、挙げた要素（機体の事実、`tailscale` など）も入っていなければ止めます。例: `windows_vm.star` の `needs = ["nixos_system", "local_kvm"]` により、WSL で `write_doc_with_windows` を選ぶと、足りない名前を示して止まります。

機体の要素を持たないホスト（`tests/hosts/`）は、機体の事実を `purposes` に書きます。

## 自分用サーバとクライアント

機体による違いを扱う順番は [構成の境界](../architecture/configuration.md#機体による違いを受け持つ場所) にあります。機体によって変わる処理のうち、機体の事実（物理的な条件）で決まらないものは、自分用サーバ（サービスを公開する側）とクライアント（サービスを使う側）に分けます。
「どの機体でするか」を機体ごとに書くと、行動と機体の組み合わせを人が管理することになり、1台に限るものは2台に書いたときに止める仕組みも要るからです。

- サーバの側: サーバを置くホストの利用者が、`purposes` に `run_home_server` を書きます。`run_home_server.star` は `requires` に `serve_quaderno_archive`（Quaderno のアーカイブ）、`serve_xsaved`（xsaved）、`serve_workspace`（ssh でつながる作業場所）、`serve_alook`（Alook）、`serve_remote_desktop`（GNOME の画面の RDP）、`serve_builds`（Nix のビルドの引き受け）、`stay_awake`（自動 suspend の停止）を挙げ、サーバを動かす利用者を linger にします。
- クライアントの側: `use_quaderno_archive`、`use_xsaved`、`use_alook` が、ssh でサーバに接続します。使う行動か手段が `requires` に挙げます。どれも、自分用サーバへ ssh で接続する手段の `find_home_server` だけを `requires` に挙げ、`find_home_server` が鍵（`lan_ssh_key`）を置き、`needs` に `tailscale` を挙げます。tailnet に入らない機体で選ぶと confgen が止まります。サーバの機体でも、同じ内容で自分に接続します。利用者が自分で選ぶクライアントは行動にします。spin713 の `program_on_home_server`（ファイルを sshfs で開き、build と Alook を自分用サーバで動かす）がその例です。
- 外部のサービスを使う側: サービスが外部（PyPI や uv が配る Python）にあるときは、使う側の手段だけを書きます。`use_uv` が `requires` の `nix_ld` を入れます。
- 接続先: どこにも書きません。`find_home_server` が、仮引数 `roles` から、`run_home_server` が入っている利用者のいるただ 1 つのホストを求め、公開値 `services` で、サービスの要素（`serve_xsaved` など）ごとに、動かしている利用者と接続名（`desktop-ts` など）を渡します。サーバのホストの値（xsaved の `web_port` など）は `machines` から読みます。

`run_home_server` が入っている利用者のいるホストが 0 個か 2 個以上のとき、サービスを動かす利用者が ssh のログインを受け付けないとき（`accept_ssh_server` が入っていない）、同じサービスを 2 人が動かしているときは、`find_home_server` が生成を止めます。

サーバのホストの `purposes` を変えると、クライアントのホストの生成結果も変わります。クライアントのホストでも switch してください。

## ホストとユーザーの値

ホストのファイルの次のキーは、flake が構成を作るときに読みます。

| キー | 中身 |
|---|---|
| `system` | `x86_64-linux` など |
| `kind` | `nixos`（NixOS の構成）か `home`（standalone の Home Manager）。無いファイルは構成を作らず、tests の架空のホストにだけ使う |
| `state_version`、`timezone` | NixOS と Home Manager の stateVersion、タイムゾーン |
| `machine` | 機体の要素の名前。省くと、利用者の `purposes` だけから要素が決まる（tests の架空のホスト） |
| `[[users]]` | `name`、`purposes`、`admin`、`home_manager = false`（Home Manager を使わない人）、`initial_hashed_password` |

`machine` と `purposes` 以外のキーは、要素が仮引数 `host` で読めます（`host.echo_cancel_source`）。全ホストのファイルは仮引数 `machines` で読めます（`machines.all["nixos-desktop"]["system"]`）。`host.users` と `machines` からは `purposes` と `machine` を外してあり、要素はどの要素が入っているかを値として読めません。

ホストのファイルの `[[users]]` の `name` と `purposes` 以外のキーは、仮引数 `user` で読めます（`user.xsaved`）。`[[users]]` の直後に `[users.<名前>]` と書くと、その利用者の表になります。

`config/owner.toml` のキーは、仮引数 `owner` で読めます（`owner.git_username`）。どのホストのどの利用者についても同じ値です。利用者に入るのは、`owner` を読む要素がその利用者について入ったときだけです。

仮引数 `roles` では、役目の要素（定義に `role = True` と書いた要素）が、どのホストのどの利用者について入っているかを読めます。`roles.hosts["nixos-desktop"]["pomu"]` は、その利用者について入っている役目の要素の名前のリストです。役目の要素が 1 つも入っていない利用者とホストは載りません。判定は値を使わずに決まるので、confgen は全ホストの判定を先に求めてから、要素の関数を呼びます。`roles` は接続先や名前を選ぶために使い、要素の設定値を全部出すか何も出さないかを決めるためには使いません（[規則](../architecture/rules.md) の性質 1）。

## 要素を書く

1つのファイルが1つの要素です。ファイル名が要素の名前です。書けるのは次の9個と、`_` で始まる補助の名前だけです。

| 名前 | 中身 |
|---|---|
| `requires = [...]` | 値を読まずに使う要素（行動が使う道具など） |
| `def public(...)` | 他の要素が読める値の辞書を返す |
| `def writes(...)` | `write(相手, 値)` のリストを返す |
| `def config(..., incoming)` | ホスト全体の設定。`{"nixos": {"option.path": 値}, "nixos_imports": [...]}` を返す。`incoming` は自分への書き込みの一覧（`w.source`、`w.value`） |
| `def user_config(..., incoming)` | 利用者ごとの設定。要素が入る利用者ごとに呼ばれ、`{"home": {...}, "home_imports": [...], "nixos": {...}}` を返す。`nixos` には、その利用者だけの NixOS の設定（`("users", "users", user.name, "extraGroups")` など）を書く |
| `when = [...]` | 派生要素の条件。同じ利用者について、挙げた要素がすべて入るときだけ、この要素が入る |
| `needs = [...]` | この要素が入る利用者について、入っていなければならない要素（機体の事実など）。足りなければ止める |
| `kind = "..."` | `"machine"`（機体の要素）か `"machine_fact"`（機体の事実）。行動と道具には書かない |
| `role = True` | 役目の要素。ほかのホストの要素が、仮引数 `roles` で、この要素が入っている利用者を読める |

`config` は、利用者によって変わる値を読めません。利用者によって変わる値は、`user` と、`public` が利用者によって変わる値を読む要素の公開値です（`checkout.root` など）。`public` と `writes` は、利用者によって変わる値を読むと利用者ごとに呼ばれ、読まなければホストごとに1回呼ばれます。

関数の仮引数の名前が、参照する要素の名前です。仮引数には相手の公開値が属性として渡ります（`util_linux.findmnt`）。`write` の第1引数には、`writes` の仮引数の名前をそのまま書きます。

仮引数 `host`、`user`、`machines` は confgen が渡す要素で、要素のファイルはありません。ファイルの値のほかに、`host.system`、`host.linux`、`host.darwin` と、`user.name`、`user.home` を読めます。

option のパスに `.` を含む名前があるときは、タプルで書きます（`("xdg", "dataFile", "nvim/nix/features.lua", "text")`）。外部の flake の Home Manager モジュールが要るときは、`user_config` が `"home_imports": [module("memex-nix", "homeModules.memex")]` を返します。NixOS のモジュールは `config` が `"nixos_imports"` で返します。

機体の性質で入るかどうかが変わる要素は、性質を表す要素を `when` に挙げます。例: [antigravity_cli.star](../../config/elements/antigravity_cli.star) は `when = ["claude_code", "x86_64_linux"]` で、`x86_64_linux` は x86_64 の Linux の機体の要素が `requires` に挙げます。値を見て設定を空にする書き方は、次の節のとおり止められます。

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
- `machine` に `kind = "machine"` でない要素を書く、機体の要素を `requires` か `when` か `purposes` に書く
- 機体の事実を、機体の要素以外の `requires` に書く、機体の要素を持つホストの `purposes` に書く
- 要素が入る利用者について、`needs` に挙げた要素が入っていない

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
