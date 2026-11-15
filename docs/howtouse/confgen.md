# ユーザーが選ぶ利用目的ごとの設定（confgen）

規則: [flake_public のあるべき姿](../architecture/rules.md)
設計: [confgen.md](../architecture/confgen.md)
実装: [config/](../../config/)（コンポーネント、ホスト、ユーザー）/ [tools/confgen](../../tools/confgen/)（評価と検査）/ [NixOS への反映](../../modules/nixos/confgen.nix) / [Home Manager への反映](../../modules/home-manager/confgen.nix)

`config/elements/` の Starlark のファイルが、設定のコンポーネントを1つずつ定義します。ホストのファイル `config/hosts/<ホスト名>.toml`（standalone の Home Manager では `<構成名>.toml`）は、ハードウェアプロファイルを `machine` で選び、ユーザーごとに利用目的のコンポーネントを `[[users]]` の `purposes` で選びます。ユーザーごとに、ハードウェアプロファイルと利用目的から十分条件のつながりをたどれるコンポーネントが、そのユーザーについて有効なコンポーネントになります。switch の評価の途中で confgen が動くので、手で実行する手順はありません。

値は TOML に、処理はコンポーネント定義に書きます。ホストとユーザーの値は `config/hosts/<ホスト名>.toml`、リポジトリの持ち主の値は `config/owner.toml` に置きます。

## 利用目的を選ぶ・外す

ホストのファイルの `[[users]]` の `purposes` に、利用目的のコンポーネントの名前を足すか消します。

```toml
machine = "machine_nixos_spin713"

[[users]]
name = "pomu"
purposes = ["programming", "read_materials"]
```

利用目的を外すと、そのユーザーについて、その利用目的からしか導けないコンポーネントが外れます。外れたコンポーネントの Home Manager の設定はそのユーザーから消えます。ほかのユーザーについて有効なコンポーネントのシステム設定は残ります。

`purposes = []` のユーザーには、ハードウェアプロファイルから導けるコンポーネントだけが入ります。`purposes` はユーザーごとに必ず書きます。

## プラットフォームの事実

ホストによって入るかどうかが変わるコンポーネントは、ホストの名前ではなく、プラットフォームの事実を条件にします。

- ハードウェアプロファイル（`kind = "machine"`）は、ホストのファイルの `machine` にだけ書けます。ほかのコンポーネントの `requires` には書けません。
- プラットフォームの事実（`kind = "machine_fact"`）は、設定では用意できないホストの性質です。例: `x86_64_linux`、`nixos_system`（confgen が NixOS の設定を作る）、`rocm_compute`（ROCm で GPU の計算ができる）、`local_kvm`（KVM の仮想マシンを動かせる）。

プラットフォームの事実は、ハードウェアプロファイルの `requires` にだけ書けます。利用目的や道具の `requires` に書くと止まります。利用目的を選んだだけで「KVM を動かせる」が真になってしまうからです。

プラットフォームの事実が要るコンポーネントは、その事実を `needs` に書きます。`needs` は十分条件のうち、インストールでは用意できない項目で、confgen は入れずに確かめます。

```python
# mimikopi.star
needs = ["x86_64_linux", "rocm_compute"]
```

`make_music` の `requires` に `mimikopi` があるので、ROCm のないホストで `make_music` を選ぶと止まります。どのホストでどのコンポーネントを使うかは、ユーザーがホストごとに選ぶ利用目的で決めます。ホストや組み合わせで入れたり入れなかったりする書き方（`when`）はありません。二つのコンポーネントがそろって初めて要るものは、両方をたどる利用目的の `requires` に並べます（例: `program_on_home_server` の `direnv_on_sshfs`）。

新しいホストを足すときは、ハードウェアプロファイルの `requires` に、そのプラットフォームの事実を書くだけです。

`needs = [...]` は、有効なコンポーネントが決まった後の検査で、コンポーネントを入れはしません。コンポーネントが有効なユーザーについて、挙げたプラットフォームの事実がそのホストで成り立っていなければ止めます。例: `windows_vm.star` の `needs = ["nixos_system", "local_kvm"]` により、WSL で `write_doc_with_windows` を選ぶと、足りない名前を示して止まります。

ハードウェアプロファイルを持たないホスト（`tests/hosts/`）は、プラットフォームの事実を `purposes` に書きます。

## 自分用サーバとクライアント

ホストによる違いを扱う順番は [構成の境界](../architecture/configuration.md#ホストによる違いを受け持つ場所) にあります。ホストによって変わる処理のうち、プラットフォームの事実（物理的な条件）で決まらないものは、自分用サーバ（サービスを公開する側）とクライアント（サービスを使う側）に分けます。
「どのホストでするか」をホストごとに書くと、利用目的とホストの組み合わせを人が管理することになり、1台に限るものは2台に書いたときに止める仕組みも要るからです。

- サーバの側: サーバを置くホストのユーザーが、`purposes` に `run_home_server` を書きます。`run_home_server.star` は `requires` に `serve_quaderno_archive`（Quaderno のアーカイブ）、`serve_xsaved`（xsaved）、`serve_workspace`（ssh でつながる作業場所）、`serve_alook`（Alook）、`serve_remote_desktop`（GNOME の画面の RDP）、`serve_builds`（Nix のビルドの引き受け）、`stay_awake`（自動 suspend の停止）を挙げ、サーバを動かすユーザーを linger にします。
- クライアントの側: `use_quaderno_archive`、`use_xsaved`、`use_alook` が、ssh でサーバに接続します。使う利用目的か手段が `requires` に挙げます。どれも、自分用サーバへ ssh で接続する手段の `find_home_server` だけを `requires` に挙げ、`find_home_server` が鍵（`lan_ssh_key`）を置き、`requires` の `connect_ssh_tailnet` で tailnet に入って tailnet の接続名（`desktop-ts` など）の Host ブロックを書きます。会社 PC の WSL で選ぶと、WSL のハードウェアプロファイルが読み込む assertion（[isolation.nix](../../hosts/nixos-work-wsl/isolation.nix)）が評価を止めます。サーバのホストでも、同じ内容で自分に接続します。ユーザーが自分で選ぶクライアントは利用目的にします。spin713 の `program_on_home_server`（ファイルを sshfs で開き、build と Alook を自分用サーバで動かす）がその例です。
- 外部のサービスを使う側: サービスが外部（PyPI や uv が配る Python）にあるときは、使う側の手段だけを書きます。`use_uv` が `requires` の `nix_ld` を入れます。
- 接続先: どこにも書きません。`find_home_server` が、仮引数 `roles` から、`run_home_server` が有効なユーザーのいるただ 1 つのホストを求め、公開値 `services` で、サービスのコンポーネント（`serve_xsaved` など）ごとに、動かしているユーザーと接続名（`desktop-ts` など）を渡します。サーバのホストの値（xsaved の `web_port` など）は `machines` から読みます。

`run_home_server` が有効なユーザーのいるホストが 0 個か 2 個以上のとき、サービスを動かすユーザーが ssh のログインを受け付けないとき（そのホストに `ssh_server` がない、またはそのユーザーが `personal_files` を選んでいない）、同じサービスを 2 人が動かしているときは、`find_home_server` が生成を止めます。

サーバのホストの `purposes` を変えると、クライアントのホストの生成結果も変わります。クライアントのホストでも switch してください。

## ホストとユーザーの値

ホストのファイルの次のキーは、flake が構成を作るときに読みます。

| キー | 中身 |
|---|---|
| `system` | `x86_64-linux` など |
| `kind` | `nixos`（NixOS の構成）か `home`（standalone の Home Manager）。無いファイルは構成を作らず、tests の架空のホストにだけ使う |
| `state_version`、`timezone` | NixOS と Home Manager の stateVersion、タイムゾーン |
| `machine` | ハードウェアプロファイルの名前。省くと、ユーザーの `purposes` だけからコンポーネントが決まる（tests の架空のホスト） |
| `[[users]]` | `name`、`purposes`、`admin`、`home_manager = false`（Home Manager を使わない人）、`initial_hashed_password` |

`machine` と `purposes` 以外のキーは、コンポーネントが仮引数 `host` で読めます（`host.echo_cancel_source`）。全ホストのファイルは仮引数 `machines` で読めます（`machines.all["nixos-desktop"]["system"]`）。`host.users` と `machines` からは `purposes` と `machine` を外してあり、コンポーネントはどのコンポーネントが入っているかを値として読めません。

ホストのファイルの `[[users]]` の `name` と `purposes` 以外のキーは、仮引数 `user` で読めます（`user.xsaved`）。`[[users]]` の直後に `[users.<名前>]` と書くと、そのユーザーの表になります。

`config/owner.toml` のキーは、仮引数 `owner` で読めます（`owner.git_username`）。どのホストのどのユーザーについても同じ値です。ユーザーに入るのは、`owner` を読むコンポーネントがそのユーザーについて有効なときだけです。

仮引数 `roles` では、役目のコンポーネント（定義に `role = True` と書いたコンポーネント）が、どのホストのどのユーザーについて入っているかを読めます。`roles.hosts["nixos-desktop"]["pomu"]` は、そのユーザーについて入っている役目のコンポーネントの名前のリストです。役目のコンポーネントが 1 つも入っていないユーザーとホストは載りません。有効なコンポーネントは値を使わずに決まるので、confgen は全ホストについて先に求めてから、コンポーネントの関数を呼びます。`roles` は接続先や名前を選ぶために使い、コンポーネントの設定値を全部出すか何も出さないかを決めるためには使いません（[規則](../architecture/rules.md) の規則 A の4つめ）。

## コンポーネント定義を書く

1つのファイルが1つのコンポーネントです。ファイル名がコンポーネントの名前です。書けるのは次の8個と、`_` で始まる補助の名前だけです。

| 名前 | 中身 |
|---|---|
| `requires = [...]` | 値を読まずに使うコンポーネント（利用目的が使う道具など） |
| `def public(...)` | 公開値の辞書を返す |
| `def writes(...)` | 寄与する値を `write(相手, 値)` のリストで返す |
| `def config(..., incoming)` | システム設定。`{"nixos": {"option.path": 値}, "nixos_imports": [...]}` を返す。`incoming` は自分への寄与値の一覧（`w.source`、`w.value`） |
| `def user_config(..., incoming)` | ユーザー設定。コンポーネントが有効なユーザーごとに呼ばれ、`{"home": {...}, "home_imports": [...], "nixos": {...}}` を返す。`nixos` には、そのユーザーだけの NixOS の設定（`("users", "users", user.name, "extraGroups")` など）を書く |
| `needs = [...]` | 十分条件のうち、プラットフォームの事実。このコンポーネントが有効なユーザーのいるホストで成り立っていなければ止める |
| `kind = "..."` | `"machine"`（ハードウェアプロファイル）か `"machine_fact"`（プラットフォームの事実）。利用目的と道具には書かない |
| `role = True` | 役目のコンポーネント。ほかのホストのコンポーネントが、仮引数 `roles` で、このコンポーネントが有効なユーザーを読める |

`config` は、ユーザー依存の値を読めません。ユーザー依存の値は、`user` と、`public` がユーザー依存の値を読むコンポーネントの公開値です（`checkout.root` など）。`public` と `writes` は、ユーザー依存の値を読むとユーザーごとに呼ばれ、読まなければホストごとに1回呼ばれます。

関数の仮引数の名前が、参照するコンポーネントの名前です。仮引数には相手の公開値が属性として渡ります（`util_linux.findmnt`）。`write` の第1引数には、`writes` の仮引数の名前をそのまま書きます。

仮引数 `host`、`user`、`machines` は confgen が渡すコンポーネントで、コンポーネント定義のファイルはありません。ファイルの値のほかに、`host.system`、`host.linux`、`host.darwin` と、`user.name`、`user.home` を読めます。

option のパスに `.` を含む名前があるときは、タプルで書きます（`("xdg", "dataFile", "nvim/nix/features.lua", "text")`）。外部の flake の Home Manager モジュールが要るときは、`user_config` が `"home_imports": [module("memex-nix", "homeModules.memex")]` を返します。NixOS のモジュールは `config` が `"nixos_imports"` で返します。

ホストの性質が要るコンポーネントは、性質を表すプラットフォームの事実を `needs` に挙げます。例: [antigravity_cli.star](../../config/elements/antigravity_cli.star) は `needs = ["x86_64_linux"]` で、`claude_code` の `requires` に入っています。`x86_64_linux` は x86_64 の Linux のハードウェアプロファイルが `requires` に挙げます。値を見て設定を空にする書き方は、次の節のとおり止められます。

書いた値を confgen の外（Lua やシェルスクリプト）が読み、その読み手が別のコンポーネントで有効になるときは、confgen はその依存を見つけられません。読み手を有効にするコンポーネントを `requires` に書きます。例: [tinymist_on_sshfs.star](../../config/elements/tinymist_on_sshfs.star) は `nvim_lsp` が有効にする Lua が読む値を書くので、`requires` に `nvim_lsp` を挙げています。

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

- 仮引数に挙げていないコンポーネントを使う、使わない仮引数を書く
- `when` を書く
- `needs` に、プラットフォームの事実でないコンポーネントを書く
- 仮引数で受けたコンポーネントを公開値や寄与値に入れて渡す
- 公開値を書き換える（`append` など）
- `load` を書く
- `config` がユーザー依存の値を読む、`config` が `home` を返す
- コンポーネントが有効なのに、`config` と `writes` が何も返さない（ホストごと）、`user_config` と `writes` が何も返さない（ユーザーごと）。`return {}` や `return []` で設定を出さない書き方がこれにあたる
- ユーザーごとに呼ばれる `writes` が、`user_config` を持たないコンポーネントに寄与する
- ホストのファイルの先頭に `purposes` を書く、`[[users]]` に `purposes` を書かない
- `machine` に `kind = "machine"` でないコンポーネントを書く、ハードウェアプロファイルを `requires` か `purposes` に書く
- プラットフォームの事実を、ハードウェアプロファイル以外の `requires` に書く、ハードウェアプロファイルを持つホストの `purposes` に書く
- コンポーネントが有効なユーザーについて、`needs` に挙げたコンポーネントが入っていない

## 変更の範囲を見る

あるコンポーネントを変えたときに影響するコンポーネントを表示します。

```sh
cd tools/confgen
nix shell nixpkgs#go -c go run . explain ../../config nixos-spin713 x86_64-linux util_linux
```

そのコンポーネントを参照するコンポーネント、寄与するコンポーネントと、そのコンポーネントが値を出す option を表示します。

あるコンポーネントがなぜユーザーについて入っているかを、起点（ハードウェアプロファイルか `purposes`）までたどって表示します。利用目的を外しても残るコンポーネントは、ほかの利用目的からの経路が表示されます。

```sh
nix shell nixpkgs#go -c go run . why ../../config nixos-spin713 x86_64-linux pomu util_linux
```

## 検査

confgen の build がテスト（[confgen_test.go](../../tools/confgen/confgen_test.go)）を実行します。規則に反する書き方を止めること、ユーザーごとに自分の利用目的から導けるコンポーネントだけが入ることを確かめます。switch の評価はこの build を通るので、テストが失敗すると switch できません。

check `elements-alone`（[tests/elements/confgen.nix](../../tests/elements/confgen.nix)）は `confgen alone` を実行し、どのコンポーネントも、ホストの最初のユーザーがそれ1つだけを選んだときに生成できることを確かめます。ホストの値とホストは、そのコンポーネントを生成している既存のホストのものを使います。上の依存を書き忘れたコンポーネントはここで止まります。2つのコンポーネントが同じ値に書いて衝突する場合は見つけられません。

`nixos-spin713` は手元で build しないので、デスクトップが止まっているときは `--max-jobs 1` を付けて switch します（[remote-build.md](./remote-build.md)）。
