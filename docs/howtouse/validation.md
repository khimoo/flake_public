# 変更の検証

設計: [構成の境界](../architecture/configuration.md)
実装: [check.sh](../../scripts/check.sh) / [モジュール検証](../../tests/default.nix) / [文書検証](../../scripts/check-docs.py)

## 変更範囲から検証を選ぶ

変更した境界を確認できる最小の検証を選びます。一括検証を毎回の既定にはしません。

| 変更範囲 | 選ぶ検証 |
|---|---|
| 文書のみ | `python3 scripts/check-docs.py .` と `git diff --check` |
| パッケージ | 変更したパッケージを単体 build し、既存の installCheck まで確認（下記） |
| ホスト・Home Manager モジュール | `bash scripts/check.sh`。そのホストや機能に固有の check があれば `--all` |
| エディタ | 対象設定・Lua などの構文と、対象機能の実機確認 |
| 構成の組み立て、overlay、評価に IFD が絡む変更 | `bash scripts/check.sh --full` |

回帰には壊れた契約を確認する既存の check を拡張するか、対象を絞った確認を追加し、実装の文面をなぞるだけのテストや新しい評価基盤を安易に増やしません。

重い評価・build はデスクトップで行い、`nixos-spin713` で全体検証を実行しません。ユーザーが検証省略を指定した場合は従い、未検証と報告します。文書整備の進め方は [文書整備](documentation.md) を参照してください。

## check.sh

Nix（flakes有効）、Python 3、Git、Bashが必要です。世代切替は行いません。

```sh
bash scripts/check.sh          # 文書、全ホストと全 home の軽い評価、共通の check
bash scripts/check.sh --all    # ホストや機能に固有の check も build する
bash scripts/check.sh --full   # toplevel の評価、nix flake check、全 system の check の評価も行う
```

check は [tests/default.nix](../../tests/default.nix) で二つの集合に分けてあり、`check.sh` は各 check の `checkSet` を見て build する対象を選びます。どの check がどちらに入るかの正本はその定義です。

- `common`：どの変更でも確かめる契約。架空のホストと Home Manager の構成で、ユーザーの分離、オプションの型と必須パス、未対応 OS での機能の拒否、activation の依存名、偽の Git と sops に対する clone と秘密の配置・更新の動作などを確かめる。
- `feature`：実際のホストや個別の機能に固有の確認。WSL とデスクトップの構成の契約、GNOME 拡張の対応版、各コマンドを偽の道具に対して動かすテストなど。

引数なしでは、全 NixOS ホストの assertions と `system.path` の drvPath、`homeConfigurations` の activation の drvPath を評価します。`system.build.toplevel` は評価しません。desktop と spin713 の全画面を透かす mutter のパッチは `system.replaceDependencies` を使い、toplevel の評価中にシステム closure の参照を生成する import-from-derivation（IFD）が起き、パッチを当てた mutter の build を待つからです。`--full` は先に全ホストの toplevel を評価してから `nix flake check --no-build --no-update-lock-file` を行います（未生成の `references.nix.drv` に対して `nix flake check` が失敗するため）。`--no-build` はこの評価依存をなくす指定ではありません。全画面の透過の見た目は、switch 後に目で確かめます。

[CI](../../.github/workflows/check.yml) は Linux runner で `--full` を実行します。fresh な CI では GUI・音楽制作を含む多数の store 依存を取得・build するので、十分なディスク容量と時間が必要です。リモートの CI 実行は push 後に確認してください。

Git flakeは未追跡ファイルを読みません。新しいファイルは `git add <path>`（差分をstageしたくなければ `git add -N <path>`）してから検証します。lock更新は検証に混ぜません。

## 確認できないこと

本人の checkout・秘密鍵にはアクセスせず、実際のネットワーク操作や環境適用は行いません。Darwin構成はLinuxから評価できますが、macOSバイナリのbuild・activation・GUI動作を検証したことにはなりません。外部リンクの到達性と文書内容の正しさも、自動リンク検証の対象外です。

## 対象別の確認手順

パッケージ更新時はリポジトリのルートで対象を単体 build し、installCheck まで実行します。
Happy の例:

```sh
nix build --impure --expr '(builtins.getFlake (toString ./.)).nixosConfigurations.nixos-desktop.pkgs.callPackage ./packages/happy { }'
```

`happy` を `dpt-rp1-py`、`uv-mode`、`antigravity-cli` に置き換えると各定義を確認できます。
overlay 済みの Graphify は次を使います。

```sh
nix build --impure --expr '(builtins.getFlake (toString ./.)).nixosConfigurations.nixos-desktop.pkgs.graphify'
```

コマンドの確認は build 結果の `result/bin/<コマンド>` で行います。

- activation: dry-runと失敗後の再実行を確認。実際の鍵復元・cloneはユーザーが対象環境で確認。
- Neovim: Luaの構文と対象機能を実機で確認。live checkoutの変更はrebuildを待たず反映されます。

Neovim の Markdown パーサ指定のマージは、lazy.nvim を導入済みの Neovim で
リポジトリのルートから確認します。プラグインのダウンロードやパーサのビルドは行いません。

```sh
nvim --headless -n -u NONE -i NONE -l scripts/check-neovim-parser-merge.lua
```

[回帰チェック](../../scripts/check-neovim-parser-merge.lua) は実際の lazy.nvim のマージ処理を使い、
共通 spec と Markdown spec の読み込み順を入れ替えても必要なパーサが残ることを確認します。
背景は [spec マージの設計](../../modules/home-manager/dev/neovim/config/docs/architecture/spec-merge.md) を参照。

適用は利用者自身がREADMEのコマンドで行い、結果と必要なら復旧手順を確認します。

## 原因を絞り込むときの評価

`system.replaceDependencies` を使うdesktopとspin713の `system.build.toplevel` は、評価だけでもシステム全体の取得とbuildを待ちます。設定のエラーや警告を探すだけなら、置換を通らない値を先に評価します。

```sh
h=nixos-desktop
nix eval --json .#nixosConfigurations.$h.config.assertions \
  --apply 'as: map (a: a.message) (builtins.filter (a: !a.assertion) as)'
nix eval --json .#nixosConfigurations.$h.config.warnings
nix eval --raw .#nixosConfigurations.$h.config.system.path.drvPath
nix eval --raw .#nixosConfigurations.$h.config.system.build.etc.drvPath
```

この切り分け用の評価では、home-manager-filesのようにbuildで初めて出る失敗は見つからず、devShellsも対象外です。最後は冒頭の選択基準に従い、対象のbuild・check、または必要な場合に一括検証を行います。

リファクタで挙動が変わっていないことを確かめるとき、`system.build.toplevel.drvPath` の比較は使えません。[secrets.nix](../../modules/home-manager/secrets.nix) が暗号文をflakeのソース内のパスでactivationに埋め込むので、repoのどのファイルを変えてもdrvPathが変わります。代わりに `config.system.path` のストアパスと、変更した値の評価結果を前後で比べます。`nix-diff` は入力が変わったderivationの環境の比較を省くので、差分が出なかったことを根拠にしません。
