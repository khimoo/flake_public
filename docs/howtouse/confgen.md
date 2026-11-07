# 目的ごとの設定（confgen）

設計: [confgen.md](../architecture/confgen.md)
実装: [config/](../../config/)（要素とホスト）/ [tools/confgen](../../tools/confgen/)（評価と検査）/ [confgen.nix](../../modules/home-manager/confgen.nix)（Home Manager への反映）

`config/elements/` の Starlark のファイルが、設定の要素を1つずつ定義します。ホストは `config/hosts/<ホスト名>.toml`（standalone の Home Manager では `<構成名>.star`）で目的を選び、選んだ目的から参照をたどれる要素と、条件がそろった派生要素だけが Home Manager と NixOS の設定になります。switch の評価の途中で confgen が動くので、手で実行する手順はありません。

## 目的を選ぶ・外す

`config/hosts/<ホスト名>.toml` の `purposes` に、目的の要素の名前を足すか消します。

```python
purposes = ["daily_editing", "sshfs_editing"]
```

目的を外すと、その目的からしか参照されていない要素と、その目的を条件に持つ派生要素が消えます。

## 要素を書く

1つのファイルが1つの要素です。ファイル名が要素の名前です。書けるのは次の5つと、`_` で始まる補助の名前だけです。

| 名前 | 中身 |
|---|---|
| `requires = [...]` | 値を読まずに使う要素（目的が使う道具など） |
| `def public(...)` | 他の要素が読める値の辞書を返す |
| `def writes(...)` | `write(相手, 値)` のリストを返す |
| `def config(..., incoming)` | `{"home": {"option.path": 値}, "nixos": {"option.path": 値}}` を返す。`incoming` は自分への書き込みの一覧（`w.source`、`w.value`） |
| `when = [...]` | 派生要素の条件。挙げた要素がすべて入るときだけ、この要素が入る |

関数の仮引数の名前が、参照する要素の名前です。仮引数には相手の公開値が属性として渡ります（`util_linux.findmnt`）。`write` の第1引数には、`writes` の仮引数の名前をそのまま書きます。

仮引数 `host` と `user` は confgen が渡す要素で、ファイルはありません。`host.system`、`host.linux`、`host.darwin` と、`user.name`、`user.home` を読めます。

option のパスに `.` を含む名前があるときは、タプルで書きます（`("xdg", "dataFile", "nvim/nix/features.lua", "text")`）。外部の flake の Home Manager モジュールが要るときは、`config` が `"home_imports": [module("memex-nix", "homeModules.memex")]` を返します。

Nix にしか作れない値は印で書きます。

| 印 | 値 |
|---|---|
| `pkg("sshfs")`、`pkg("vimPlugins.lazy-nvim")` | パッケージ |
| `exe("util-linux", "findmnt")` | パッケージの中のコマンドのパス |
| `concat("前", exe(...), "後")` | 印を含む文字列 |
| `luaPackages(["lpeg"])` | Neovim の Lua のパッケージを選ぶ関数 |
| `checkoutLink("modules/...")` | checkout への symlink |
| `lua(値)` | 値を Lua の式にした文字列 |
| `module("input", "homeModules.x")` | flake input の Home Manager モジュール（`home_imports` に入れる） |

`str()` や `%` で印を文字列にすると、confgen がエラーにします。

## 止められる書き方

次の書き方は、評価の途中で confgen がファイル名と行を示して止めます。

- 仮引数に挙げていない要素を使う、使わない仮引数を書く
- 派生要素を仮引数か `requires` で挙げる
- 受け取った要素を公開値や書き込みの値に入れて渡す
- 公開値を書き換える（`append` など）
- `load` を書く

## 変更の範囲を見る

ある要素を変えたときに影響する要素を表示します。

```sh
cd tools/confgen
nix shell nixpkgs#go -c go run . explain ../../config nixos-spin713 util_linux
```

その要素を読む要素、書き込む要素、条件に持つ派生要素と、その要素が値を出す option を表示します。

## 検査

confgen の build がテスト（[confgen_test.go](../../tools/confgen/confgen_test.go)）を実行します。規則に反する書き方を止めること、目的を外すと専用の要素が消えること、派生要素が条件のそろったときだけ入ることを確かめます。switch の評価はこの build を通るので、テストが失敗すると switch できません。

`nixos-spin713` は手元で build しないので、デスクトップが止まっているときは `--max-jobs 1` を付けて switch します（[remote-build.md](./remote-build.md)）。
