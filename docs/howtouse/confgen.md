# ユーザーが選ぶ利用目的ごとの設定（confgen）

規則: [flake_public のあるべき姿](../architecture/rules.md)
設計: [confgen.md](../architecture/confgen.md)
実装: [config/](../../config/)（コンポーネント、ホスト、ユーザー）/ [tools/confgen](../../tools/confgen/)（評価と検査）/ [NixOS への反映](../../modules/nixos/confgen.nix) / [Home Manager への反映](../../modules/home-manager/confgen.nix)

`config/elements/` 配下の各 Starlark ファイルが、設定のコンポーネント（element）を1つずつ定義します。
各ホストの設定ファイル `config/hosts/<ホスト名>.toml`（standalone Home Manager では `<構成名>.toml`）では、`machine` でハードウェアプロファイルを指定し、`[[users]]` の `purposes` でユーザーごとの利用目的（コンポーネント群）を選択します。

各ユーザーで有効になるコンポーネントは、ハードウェアプロファイルおよび利用目的から十分条件のつながりをたどることで決定されます。NixOS や Home Manager の switch 評価時に confgen が自動実行されるため、手動でコマンドを実行する必要はありません。

設計原則は「値は TOML に、処理はコンポーネント定義に書く」です。ホストやユーザー固有の値は `config/hosts/<ホスト名>.toml` に、リポジトリ所有者の共通値は `config/owner.toml` に記述します。

## 利用目的を選ぶ・外す

ホストファイルの `[[users]]` にある `purposes` 配列に対し、利用目的となるコンポーネント名を追加または削除します。

```toml
machine = "machine_nixos_spin713"

[[users]]
name = "pomu"
purposes = ["programming", "read_materials"]
```

- **利用目的を外した場合**: そのユーザーにおいて、該当の利用目的からのみ導出されていたコンポーネントが除外されます。除外されたコンポーネントの Home Manager 設定はユーザー環境から削除されますが、他ユーザーで有効なコンポーネントのシステム設定（NixOS 設定）はそのまま残ります。
- **`purposes = []` とした場合**: ハードウェアプロファイルから導出されるコンポーネントのみが適用されます（`purposes` キー自体の指定は全ユーザーで必須です）。

## プラットフォームの事実

ホスト環境によって導入可否が変わるコンポーネントは、ホスト名ではなく「プラットフォームの事実」を条件として扱います。

- **ハードウェアプロファイル（`kind = "machine"`）**: ホストファイルの `machine` キーでのみ指定可能です。他のコンポーネントの `requires` に含めることはできません。
- **プラットフォームの事実（`kind = "machine_fact"`）**: 設定では用意できないホスト固有の物理的・環境的性質です（例: `x86_64_linux`、`nixos_system`（NixOS 設定を生成可能）、`rocm_compute`（ROCm による GPU 計算が可能）、`local_kvm`（KVM 仮想マシンを実行可能））。

プラットフォームの事実はハードウェアプロファイルの `requires` にのみ記述でき、利用目的やツールの `requires` に書くことは禁止されています（利用目的を選択しただけで「KVM を動かせる」といった事実が真になってしまうのを防ぐためです）。新しいホストを追加する際は、対応するハードウェアプロファイルの `requires` にそのプラットフォームの事実を列挙します。

プラットフォームの事実を前提とするコンポーネントは、`needs` にその事実を列挙します。`needs` は十分条件のうち「インストールによって自前で用意できない前提条件」を表し、confgen はそのコンポーネントを追加するのではなく、前提条件が満たされているかを検証します。

```python
# mimikopi.star
needs = ["x86_64_linux", "rocm_compute"]
```

`needs = [...]` は有効コンポーネント決定後の検証フェーズでチェックされます。有効化対象のユーザーが存在するホスト上で指定の事実が満たされていない場合、不足している項目名を明示して評価を停止します。たとえば `make_music` の `requires` に `mimikopi` が含まれている場合、ROCm を持たないホストで `make_music` を選択すると評価時にエラーになります（同様に `windows_vm.star` の `needs = ["nixos_system", "local_kvm"]` により、WSL 上で `write_doc_with_windows` を選んだ場合もエラーになります）。

どのホストでどのコンポーネントを有効にするかは、ユーザーがホストごとに選ぶ利用目的によって一意に決定されます。特定のホストや組み合わせに応じてオン/オフを切り替える条件分岐（`when` 構文など）は存在しません。2つのコンポーネントが揃って初めて必要になる機能は、双方を前提とする利用目的の `requires` に並べて定義します（例: `program_on_home_server` における `direnv_on_sshfs`）。

※ハードウェアプロファイルを持たないテスト用ホスト（`tests/hosts/`）に限り、例外的にプラットフォームの事実を `purposes` に直接指定できます。

## 自分用サーバとクライアント

ホストごとの責務の分離方針については [構成の境界](../architecture/configuration.md#ホストによる違いを受け持つ場所) を参照してください。物理的な条件（プラットフォームの事実）で決まらない差異は、「自分用サーバ（サービス提供側）」と「クライアント（サービス利用側）」に役割を分離して管理します。「どのホストで動かすか」をホスト側にベタ書きすると、組み合わせの管理が煩雑になるだけでなく、「1台限定のサービスを誤って2台に記述した際に弾く仕組み」が別途必要になるためです。

- **サーバ側**: サーバ役となるホストのユーザーが、`purposes` に `run_home_server` を指定します。`run_home_server.star` は `requires` に各サービス用コンポーネント（`serve_quaderno_archive`、`serve_xsaved`、`serve_workspace`、`serve_alook`、`serve_remote_desktop`、`serve_builds`、`stay_awake`）を列挙し、実行ユーザーの linger を有効化します。
- **クライアント側**: `use_quaderno_archive`、`use_xsaved`、`use_alook` などのクライアント用コンポーネントが SSH でサーバに接続します。これらは直接接続先を保持せず、接続手段である `find_home_server` のみを `requires` に指定します。`find_home_server` は鍵（`lan_ssh_key`）を配置し、`connect_ssh_tailnet` 経由で Tailnet に参加して接続名（`desktop-ts` など）の Host ブロックを設定します。
  - サーバ自身の上でクライアント機能を使う場合も、同一の手順で自身に接続します。
  - 会社の WSL で誤って選択された場合は、WSL のハードウェアプロファイル内の assertion（[isolation.nix](../../hosts/nixos-work-wsl/isolation.nix)）によって評価が停止します。
  - クライアントを利用目的にまとめた例として、spin713 の `program_on_home_server`（ファイルを SSHFS でマウントし、ビルドや Alook を自分用サーバで実行する構成）があります。
- **外部サービス利用側**: PyPI や uv の Python 配布など外部サービスを利用する場合は、利用側の手段のみを記述します（例: `use_uv` は `requires` に `nix_ld` を指定）。

### 接続先の自動解決

接続先ホストを静的に記述する必要はありません。`find_home_server` は引数 `roles` を参照し、`run_home_server` が有効なユーザーが存在する唯一のホストを特定します。そして公開値 `services` を通じて、各サービスコンポーネント（`serve_xsaved` など）に実行ユーザー名と接続名（`desktop-ts` など）を伝達します。サーバホスト固有の値（xsaved の `web_port` など）は `machines` から取得されます。

以下のような不正な状態が検出された場合、`find_home_server` は設定生成をエラーで中断します。

- `run_home_server` を持つホストが 0 台、または 2 台以上存在する
- サービス実行ユーザーが SSH ログインを受け付けない（`ssh_server` がない、または `personal_files` が未選択）
- 同一サービスを複数ユーザーが動かしている

※サーバ側ホストの `purposes` を変更すると、クライアント側ホストの設定生成結果にも影響します。サーバ側の変更後はクライアント側でも switch を実行してください。

## ホストとユーザーの値

ホストファイル内の以下のキーは、Flake が構成を組み立てる際に読み込まれます。

| キー | 説明 |
|---|---|
| `system` | `x86_64-linux` などのシステムアーキテクチャ |
| `kind` | `nixos`（NixOS 構成）または `home`（standalone Home Manager）。指定のないファイルは構成生成を行わず、テスト用の架空ホストとして扱われます |
| `state_version`、`timezone` | NixOS / Home Manager の stateVersion およびタイムゾーン |
| `machine` | ハードウェアプロファイル名。省略した場合はユーザーの `purposes` のみからコンポーネントを決定します（テスト用） |
| `[[users]]` | `name`、`purposes`、`admin`、`home_manager = false`（Home Manager 非使用）、`initial_hashed_password` |

コンポーネント側からは、以下の引数を介して設定値を参照できます。

- **`host` 引数**: `machine` と `purposes` 以外のキーを参照できます（例: `host.echo_cancel_source`）。
- **`machines` 引数**: 全ホストの設定値を辞書形式で参照できます（例: `machines.all["nixos-desktop"]["system"]`）。
  - ※`host.users` および `machines` からは `purposes` と `machine` が事前に除外されています。コンポーネントが「どのコンポーネントが有効化されているか」を値として直接読み取ることはできません。
- **`user` 引数**: 各 `[[users]]` エントリの `name` と `purposes` 以外のキーを参照できます（例: `user.xsaved`）。`[[users]]` の直後に `[users.<名前>]` テーブルを設けてユーザーごとのパラメータを定義できます。
- **`owner` 引数**: `config/owner.toml` に定義された値を参照できます（例: `owner.git_username`）。全ホスト・全ユーザーで共通の値となります。ただし、設定が生成されるのは `owner` を参照するコンポーネントがそのユーザーで有効な場合に限られます。
- **`roles` 引数**: 役目を持つコンポーネント（定義に `role = True` を指定したもの）が「どのホストの誰に対して有効化されているか」を取得できます。`roles.hosts["nixos-desktop"]["pomu"]` は、そのユーザーで有効な役目コンポーネント名のリストを返します（役目を持たないユーザーやホストは含まれません）。
  - 有効コンポーネントの決定は値の評価前に完了しているため、confgen は全ホストの構成を事前に解決してから各関数を呼び出します。
  - `roles` は接続先やホスト名の解決のためにのみ使用し、「設定値を出力するかどうか（空にするかどうか）」の条件分岐に使用してはなりません（[規則](../architecture/rules.md) 規則 A-4）。

## コンポーネント定義の記述

各 Starlark ファイルが 1 つのコンポーネントに対応し、ファイル名がそのままコンポーネント名となります。ファイル内に定義できるのは、以下の 9 種類のトップレベル識別子と、アンダースコア `_` で始まるプライベートな補助変数・関数のみです。

| 名前 | 説明 |
|---|---|
| `requires = [...]` | 十分条件のうち、値を読まずに使うコンポーネントのリスト（利用目的が使う道具など） |
| `def public(...)` | 公開値の辞書を返す関数 |
| `def writes(...)` | 他コンポーネントへ寄与する値を `write(対象, 値)` のリストで返す関数 |
| `def accept(...)` | 寄与を受け取るコンポーネントが、受け付ける値をキーワード引数で宣言する関数。宣言したコンポーネントへは `write(対象, 名前 = 値, ...)` で値を渡し、confgen がこの関数を呼び出した返り値が寄与値になる。仮引数の名前は受け付けるキーワード引数の名前であり、他の関数と異なりコンポーネント名を表さない（`*args` や `**kwargs` は使用不可） |
| `def config(..., incoming)` | システム全体の設定（NixOS 設定）。`{"nixos": {"option.path": 値}, "nixos_imports": [...]}` を返す。`incoming` には自身宛ての寄与値一覧（`w.source`, `w.value`）が渡る |
| `def user_config(..., incoming)` | ユーザーごとの設定。有効なユーザーごとに呼び出され、`{"home": {...}, "home_imports": [...], "nixos": {...}}` を返す。`nixos` にはそのユーザー固有の NixOS 設定（`("users", "users", user.name, "extraGroups")` など）を指定 |
| `needs = [...]` | 十分条件のうち、前提となるプラットフォームの事実。対象ユーザーが存在するホスト上で満たされていない場合エラー |
| `kind = "..."` | `"machine"`（ハードウェアプロファイル）または `"machine_fact"`（プラットフォームの事実）。通常の利用目的やツールには指定しない |
| `role = True` | 役目コンポーネントフラグ。他ホストのコンポーネントが `roles` 引数経由で有効ユーザーを検出可能になる |

- **ユーザー依存値の制約**: `config` 内でユーザー依存の値（`user` や、ユーザー依存の値を参照している `public` の値など）を直接読み取ることはできません。
- **呼び出し頻度**: `public` および `writes` は、ユーザー依存の値を参照している場合はユーザーごとに、参照していない場合はホストごとに 1 回呼び出されます。
- **引数の解決**: 各関数の仮引数名が参照先コンポーネント名に対応し、対象コンポーネントの公開値が属性として渡されます（例: `util_linux.findmnt`）。`write()` の第 1 引数には `writes` の仮引数名をそのまま渡します。`accept` を持つコンポーネントへの `write()` は値の代わりにキーワード引数を渡します（例: `write(gui_apps, pkg = pkg("vlc"))`）。`accept` に存在しない名前を渡した場合のエラーは、受け取る側ではなく寄与する側（その `write()` を返したコンポーネント）の評価時に発生します。
- **特殊な引数**: `host`、`user`、`machines` は confgen が暗黙的に提供する引数です（定義ファイルは存在しません）。これらは TOML に定義された値のほか、`host.system`, `host.linux`, `host.darwin` や `user.name`, `user.home` などの組み込みプロパティを持ちます。
- **オプションのパス表記**: パス内にドット `.` を含むオプション名は、タプル形式で記述します（例: `("xdg", "dataFile", "nvim/nix/features.lua", "text")`）。
- **モジュールのインポート**: 外部 Flake の Home Manager モジュールが必要な場合は `user_config` 内で `"home_imports": [module("memex-nix", "homeModules.memex")]` を、NixOS モジュールが必要な場合は `config` 内で `"nixos_imports"` を返します。
- **暗黙の依存の明示**: 生成された値を Lua やシェルスクリプトなど confgen の管理外で参照し、その実行系が別コンポーネントで有効化される場合は、依存関係を自動検出できません。そのため、実行環境を提供するコンポーネントを明示的に `requires` に含める必要があります（例: [tinymist_on_sshfs.star](../../config/elements/tinymist_on_sshfs.star) は `nvim_lsp` が読み込む Lua 設定値を出力するため、`requires` に `nvim_lsp` を指定しています）。

### Nix 特有値の記述

Nix の式として評価される値は、以下のヘルパーで指定します。confgen はこれを Nix 式へ変換し、生成したファイルを実際の構成へ import します。

| ヘルパー | 生成される Nix 表現 |
|---|---|
| `pkg("sshfs")`, `pkg("vimPlugins.lazy-nvim")`, `inputPkg("input", "attr")` | nixpkgs / flake input のパッケージ |
| `repoPkg("packages/x")`, `repoPkgWith("packages/x", {...})` | リポジトリ内パッケージ（`callPackage`） |
| `exe("util-linux", "findmnt")` | パッケージ内の実行可能ファイルパス |
| `concat("前", exe(...), "後")` | パッケージなどの参照を含む文字列の連結 |
| `file(name, text)`, `script(name, text)`, `scriptBin(name, text)`, `command(name, script)` | `writeText`, `writeShellScript`, `writeShellScriptBin`, `runCommand` |
| `shellApp(name, runtimeInputs, text)`, `shellAppEnv(...)` | `writeShellApplication` |
| `symlinkJoin(name, paths)`, `pythonWithModules([...])`, `pkgWithPackages(...)`, `pkgSetFn(...)` | 複合パッケージ構成 |
| `repoPath("x")`, `repoText("x")`, `flakeRev()` | リポジトリ内ファイルの store パス、内容文字列、Flake のリビジョン |
| `outOfStoreLink(path)` | Nix store 外へのシンボリックリンク（checkout からは `checkout.root` 経由で作成） |
| `activation(after, text)`, `mkAfter(v)`, `mkBefore(v)`, `gvariantTuple([...])`, `toJSON(v)` | Home Manager activation、リスト順序制御、dconf タプル、JSON 文字列化 |
| `luaPackages(["lpeg"])`, `lua(値)` | Neovim 用 Lua パッケージ選択関数、値を Lua リテラル式に変換した文字列 |
| `kernelPkg("v4l2loopback")` | 選択されたカーネルの追加モジュール |
| `module("input", "homeModules.x")`, `repoModule("hosts/x/hardware.nix")` | Nix モジュール参照（`home_imports` / `nixos_imports` 用） |

※Nix の値を表すオブジェクトを `str()` や `%` 演算子で通常の文字列に変換しようとすると、confgen はエラーを出力します。

## 禁止事項（エラーとなる書き方）

以下の記述を行った場合、confgen の評価時にファイル名と該当行が表示されて処理が停止します。

- 関数の仮引数に宣言していないコンポーネントを使用する、または宣言した仮引数を関数内で使用しない
- `when` 条件句を記述する
- `needs` にプラットフォームの事実（`kind = "machine_fact"`）以外のコンポーネントを指定する
- 引数として受け取ったコンポーネントを、そのまま公開値や寄与値に含めて転送する
- 公開値をインプレースで書き換える（`append` など）
- `load` を使用する
- `accept` を持つコンポーネントに `write(対象, 値)` の形式で書く、または `accept` を持たないコンポーネントにキーワード引数で書く
- `accept` を定義しているにもかかわらず、`config` と `user_config` の双方が `incoming` を仮引数に取らない
- `config` 内でユーザー依存の値を読み取る、または `config` から `home` 設定を返す
- 有効化されているにもかかわらず、`config` と `writes` の双方が何も返さない（ホスト単位）、あるいは `user_config` と `writes` の双方が何も返さない（ユーザー単位）（`return {}` や `return []` で設定出力を実質的にスキップする行為も該当）
- ユーザー単位で呼び出される `writes` が、`user_config` を持たないコンポーネントに対して寄与値を送信する
- ホスト設定ファイルのルートに `purposes` を書く、または `[[users]]` 内で `purposes` の指定を省略する
- `machine` に `kind = "machine"` 以外のコンポーネントを指定する、またはハードウェアプロファイルを `requires` や `purposes` に指定する
- プラットフォームの事実をハードウェアプロファイル以外の `requires` に記述する、あるいはハードウェアプロファイルを持つホストの `purposes` に記述する
- コンポーネントが有効なユーザーが存在するホストにおいて、そのコンポーネントの `needs` に列挙されたプラットフォームの事実が満たされていない

## 変更の影響範囲を確認する

特定コンポーネントの変更による影響範囲を確認するには、`explain` サブコマンドを実行します。

```sh
cd tools/confgen
nix shell nixpkgs#go -c go run . explain ../../config nixos-spin713 x86_64-linux util_linux
```

対象コンポーネントを参照しているコンポーネント、値を寄与しているコンポーネント、および対象コンポーネントが値を出力している設定オプションの一覧が表示されます。

また、あるコンポーネントが特定のユーザーでなぜ有効化されているのか（ハードウェアプロファイルまたは `purposes` からの到達経路）を調べるには、`why` サブコマンドを使用します。利用目的を外しても残留するコンポーネントがある場合、他のどの利用目的に依存しているかが可視化されます。

```sh
nix shell nixpkgs#go -c go run . why ../../config nixos-spin713 x86_64-linux pomu util_linux
```

## element のつながりと option をグラフで見る

[scripts/confgen-graph.sh](../../scripts/confgen-graph.sh) は、全ホストの構成を1つの HTML に書き出します。リポジトリのルートで実行します。

```sh
scripts/confgen-graph.sh /tmp/confgen-graph.html
```

option の最終値を求めるために全ホストの NixOS を評価するため、完了までに数分かかります。負荷の高い処理となるため、デスクトップ以外のホスト（特に `nixos-spin713`）では実行しないでください。
最終値は Flake から評価されるため、Git で追跡されていないファイルは反映されません。未追跡の element はグラフ上には表示されますが、最終値が「«値なし»」となります。

書き出された HTML をブラウザで開きます（グラフ描画ライブラリ Cytoscape を CDN 経由で読み込むため、開く際にネットワーク接続が必要です）。
開いた直後はホストのみが表示されます。各ノード右側の `▸N` ボタンで前方ノードを展開し、左側の `◂N` ボタンでホストまでのバックリンクを展開できます。再度クリックすると閉じます。ノードを開閉しても、既存の表示位置は維持されます。

ノードの種類は以下の5つです。

- **ホスト**: `config/hosts/<ホスト>.toml`
- **ユーザー**: `config/hosts/<ホスト>.toml`（該当ユーザーの `name` 行をハイライト）
- **element**: `config/elements/<名前>.star`（有効なホストやユーザーの数にかかわらず1つのノードとして表示）
- **書いた値**: 書いた element の `.star` ファイル（option パス文字列を検索して該当行をハイライト）。先頭行にその値を書いているホストやユーザーが並び、同一の値は1つのノードに集約されます
- **option の最終値**: option を宣言している nixpkgs または Home Manager のモジュール（宣言行をハイライト）。NixOS の option はホストごと、Home Manager の option はホストとユーザーごとに分かれます

※最終値は、複数の element が書いた値に対し、confgen が関与しないモジュール（nixpkgs や Home Manager の標準モジュールなど）の値や既定値を NixOS のモジュール機構が統合して決定します。
※element が option そのものではなく option の値の内側に書き込んでいる場合（例: `programs.git.settings.init.defaultBranch` が `programs.git.settings` 内のキーである場合）、最終値ノードにはパスを先頭からたどって最後に合致した option（この例では `programs.git.settings`）の宣言が表示されます。

ノードをクリックすると、右側のパネルに対応するソースファイルが表示されます。
HTML は実行時点の構成から生成されるため、構成を変更した際は再度スクリプトを実行してください。

## テストと検証

confgen のビルドプロセス内で自動テスト（[confgen_test.go](../../tools/confgen/confgen_test.go)）が実行されます。設計規則に反する記述が正しく阻止されること、各ユーザーに自身の利用目的から導出されるコンポーネントのみが適用されることが検証されます。switch の評価はこのビルドを通過する必要があるため、テストが失敗した状態では環境へ反映できません。

Flake check の `elements-alone`（[tests/elements/confgen.nix](../../tests/elements/confgen.nix)）は `confgen alone` を実行し、全コンポーネントについて「ホストの先頭ユーザーがそのコンポーネント1つのみを選択した状態でも正しく設定を生成できるか」を単体検証します（ホストおよびホスト固有値には、既存の対象ホストの設定が流用されます）。必要な依存の記述漏れがあるコンポーネントは、この検証で検出されます（※複数コンポーネントが同一オプション値に書き込んで衝突するケースは検出対象外です）。

なお、`nixos-spin713` はローカルビルドを行わないため、リモートのデスクトップマシンが停止している際は `--max-jobs 1` を付与して switch を実行してください（詳細は [remote-build.md](./remote-build.md) を参照）。

## 実際に使う生成 Nix を確認する

生成物は NixOS の設定とユーザー別の Home Manager 設定を含みます。システム構成はこのファイルを import して構築されます。たとえば desktop の生成物のパスは以下のコマンドで取得できます。

```sh
nix build --no-link --print-out-paths --impure --expr '
  let f = builtins.getFlake (toString ./.);
  in (import ./lib/confgen.nix {
    pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
  }).generate "nixos-desktop" "x86_64-linux"
'
```

出力されたパスを `cat` することで、実際に適用される option、設定値、import、および出所となった element を確認できます。設定の変更は生成物へ直接記述するのではなく、出所である element や入力元のホスト設定ファイルに記述して再生成してください。
