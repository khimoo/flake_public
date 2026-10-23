# 変更の検証

設計: [構成の境界](../architecture/configuration.md)
実装: [check.sh](../../scripts/check.sh) / [モジュール検証](../../tests/default.nix) / [文書検証](../../scripts/check-docs.py)

## 変更範囲に応じた検証の選択

変更した境界を確実に確認できる最小限の検証を選択します。一括検証を毎回デフォルトで実行することは避けてください。

| 変更範囲 | 選択する検証 |
|---|---|
| ドキュメントのみ | `python3 scripts/check-docs.py .` および `git diff --check` |
| パッケージ | 変更したパッケージを単体でビルドし、既存の installCheck まで確認（下記参照） |
| ホスト・Home Manager モジュール | `bash scripts/check.sh`（該当ホストや機能に固有の check がある場合は `--all`） |
| エディタ | 対象設定・Lua などの構文チェックと、対象機能の実機確認 |
| 構成の組み立て、overlay、評価に IFD が絡む変更 | `bash scripts/check.sh --full` |

リグレッションへの対策としては、壊れた契約を検出できるよう既存の check を拡張するか、対象を絞った確認を追加します。実装の文面を単になぞるだけのテストや、新たな評価基盤を安易に増やすことはしません。

負荷の高い評価やビルドはデスクトップ環境で実施し、`nixos-spin713` での全体検証は行いません。ユーザーから検証省略の指定があった場合はそれに従い、未検証であることを明記して報告します。ドキュメント整備の進め方については [文書整備](documentation.md) を参照してください。

## check.sh

実行には Nix（Flakes 有効）、Python 3、Git、Bash が必要です。世代の切り替えは行いません。

```sh
bash scripts/check.sh          # ドキュメント、全ホストおよび全 home の軽量評価、共通 check
bash scripts/check.sh --all    # ホストや機能に固有の check も含めてビルド
bash scripts/check.sh --full   # toplevel の評価、nix flake check、全システムの check の評価も実施
```

check は [tests/default.nix](../../tests/default.nix) で 2 つのグループに分類されており、`check.sh` は各 check の `checkSet` を参照してビルド対象を決定します。どの check がどちらに属するかは、該当ファイルの定義が正本となります。

- `common`：すべての変更で確認すべき契約。架空のホストおよび Home Manager 構成を用い、ユーザー分離、オプションの型と必須パス、非対応 OS での機能の拒否、activation の依存関係名、モックの Git や sops に対する clone と秘密情報の配置・更新動作などを検証します。
- `feature`：実機ホストや個別機能に固有の確認。WSL やデスクトップ構成の契約、GNOME 拡張機能の対応バージョン、モックツールに対する各コマンドの実行テストなどを行います。

引数なしで実行した場合、全 NixOS ホストの assertions と `system.path` の drvPath、および `homeConfigurations` の activation の drvPath を評価します。このとき `system.build.toplevel` は評価されません。desktop や spin713 で全画面を透過させる mutter のパッチには `system.replaceDependencies` が使われており、toplevel の評価中にシステムクロージャの参照を生成する IFD（Import-From-Derivation）が発生し、パッチ適用済み mutter のビルド待ちが生じるためです。`--full` を指定した場合は、先に全ホストの toplevel を評価してから `nix flake check --no-build --no-update-lock-file` を実行します（未生成の `references.nix.drv` に対して `nix flake check` を実行すると失敗するため）。なお、`--no-build` を指定してもこの評価依存はなくなりません。全画面透過の見た目については、switch 後に実機を目視で確認します。

[CI](../../.github/workflows/check.yml) は Linux runner 上で `--full` を実行します。キャッシュのない新規の CI 環境では、GUI や音楽制作関連を含む膨大なストア依存の取得・ビルドが発生するため、十分なディスク容量と実行時間が必要です。リモートでの CI 実行結果は、push 後にご確認ください。

Git flake は未追跡（untracked）ファイルを認識しません。新規ファイルは必ず `git add <path>`（差分をステージングしたくない場合は `git add -N <path>`）を行ってから検証してください。また、lock ファイルの更新は検証作業に混ぜないようにします。

## 確認できないこと

本人のローカルチェックアウトや秘密鍵にはアクセスしないため、実際のネットワーク通信を伴う操作や環境への適用は行いません。Darwin 構成は Linux 上からでも評価自体は可能ですが、macOS 用バイナリのビルド、activation、GUI の動作までを検証したことにはなりません。また、外部リンクへの到達性やドキュメント内容自体の正確性も、自動リンク検証の対象外です。

## 対象別の確認手順

パッケージ更新時は、リポジトリのルートで対象パッケージを単体ビルドし、installCheck まで実行します。
Happy の例:

```sh
nix build --impure --expr '(builtins.getFlake (toString ./.)).nixosConfigurations.nixos-desktop.pkgs.callPackage ./packages/happy { }'
```

上記の `happy` を `dpt-rp1-py`、`uv-mode`、`antigravity-cli` に置き換えることで、それぞれの定義を確認できます。
overlay 適用済みの Graphify の確認には以下を使用します。

```sh
nix build --impure --expr '(builtins.getFlake (toString ./.)).nixosConfigurations.nixos-desktop.pkgs.graphify'
```

各コマンドの動作確認は、ビルド結果として生成された `result/bin/<コマンド>` を使って行います。

- activation: dry-run の実行と、失敗後の再実行可否を確認します。実際の秘密鍵の復元や clone については、ユーザー自身が対象環境で確認してください。
- Neovim: Lua の構文チェックと対象機能の実機確認を行います。live checkout への変更は rebuild を待たずに即時反映されます。

Neovim における Markdown パーサー指定のマージ処理は、lazy.nvim 導入済みの Neovim を使用し、リポジトリのルートから確認します。プラグインのダウンロードやパーサーのビルドは不要です。

```sh
nvim --headless -n -u NONE -i NONE -l scripts/check-neovim-parser-merge.lua
```

[回帰チェック](../../scripts/check-neovim-parser-merge.lua) では、実際の lazy.nvim のマージ処理を利用し、共通 spec と Markdown spec の読み込み順を入れ替えても必要なパーサーが保持されることを確認します。背景の詳細は [spec マージの設計](../../modules/home-manager/dev/neovim/config/docs/architecture/spec-merge.md) を参照してください。

構成の適用は、利用者自身が README に記載されたコマンドに従って行い、実行結果や、必要に応じて復旧手順を確認してください。

## 原因を切り分ける際の評価手順

`system.replaceDependencies` を使用している desktop や spin713 の `system.build.toplevel` は、評価を行うだけでもシステム全体の取得とビルド待ちが発生します。設定エラーや警告の有無を確認するだけであれば、依存置換を通らない値を優先して評価します。

```sh
h=nixos-desktop
nix eval --json .#nixosConfigurations.$h.config.assertions \
  --apply 'as: map (a: a.message) (builtins.filter (a: !a.assertion) as)'
nix eval --json .#nixosConfigurations.$h.config.warnings
nix eval --raw .#nixosConfigurations.$h.config.system.path.drvPath
nix eval --raw .#nixosConfigurations.$h.config.system.build.etc.drvPath
```

ただし、この切り分け用の評価では home-manager-files のようにビルド時に初めて発生するエラーは検出できず、devShells も対象外となります。最終的には冒頭の選択基準に従い、対象のビルド・check、または必要に応じて一括検証を行ってください。

リファクタリング時に挙動の変化がないことを確かめる場合は、`config.system.path` のストアパスと、変更対象の値の評価結果を適用前後で比較します。前述のとおり `system.build.toplevel` は評価負荷が非常に重いため注意してください。なお、`nix-diff` は入力が変化した derivation の環境比較を省略する場合があるため、「差分が出なかったこと」だけをもって変更なしの根拠としないようにしてください。
