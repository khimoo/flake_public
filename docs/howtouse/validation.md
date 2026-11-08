# 変更の検証

設計: [構成の境界](../architecture/configuration.md)
実装: [check.sh](../../scripts/check.sh) / [モジュール検証](../../tests/default.nix) / [文書検証](../../scripts/check-docs.py)

## 変更範囲に応じた検証の選択

変更の影響範囲を確実に確認できる最小限の検証を選択してください。毎回デフォルトで一括検証を実行することは避けます。

| 変更範囲 | 選択する検証 |
|---|---|
| ドキュメントのみ | `python3 scripts/check-docs.py .` および `git diff --check` |
| パッケージ | 変更したパッケージを単体でビルドし、既存の installCheck まで確認（後述参照） |
| ホスト・Home Manager モジュール | `bash scripts/check.sh`（変更が影響するホストと check を選択） |
| エディタ設定 | 対象設定ファイルや Lua の構文チェックと、実機での機能確認 |
| システム構成の組み立て、overlay、IFD を伴う評価の変更 | `bash scripts/check.sh --full` |

リグレッションへの対策としては、既存の check を拡張して壊れた契約を検出できるようにするか、対象を絞った確認項目を追加します。単に実装コードの文面をなぞるだけのテストや、新しいテスト基盤の安易な追加は避けてください。

負荷の高い評価やビルドはデスクトップ環境で実施し、`nixos-spin713` での全体検証は行いません。ユーザーから検証を省略するよう指示された場合はそれに従い、未検証であることを明記して報告します。ドキュメント整備の進め方については [文書整備](documentation.md) を参照してください。

## check.sh

実行には Nix（Flakes 有効）、Python 3、Git、Bash が必要です。なお、世代の切り替え（switch）は行いません。

```sh
bash scripts/check.sh          # 変更が影響する要素・ホスト・check を検証
bash scripts/check.sh --all    # 全ホストと全 home の軽量評価、全 check のビルド
bash scripts/check.sh --full   # toplevel の評価、nix flake check、全システムの check 評価も実施
```

引数なしでは、`git merge-base HEAD @{upstream}` を基準にした差分と、未コミット・ステージ済み・未追跡ファイルの和を対象にします。上流がない場合は未コミットの変更だけを対象にします。confgen は flake と同じ nixpkgs から `nix build` で用意し、`confgen affected <repo-root> <変更ファイル>...` の JSON 出力にある `elements` と `hosts` から検証範囲を選びます。`elements = ["ALL"]` の場合は `--all` と同じ範囲を検証します。

選んだ要素、ホスト、check の名前をそれぞれ1行で表示してから、ドキュメント検証、`tools/confgen` の `go test ./...`、選択したホストの軽量評価と check のビルド、`git diff --check` を実行します。Go は confgen と同じ nixpkgs のものを使います。ホストの軽量評価は `hosts` に入った名前に限定します。変更ファイルがなければ、ドキュメント検証、Go テスト、差分の空白検査だけを実行します。

### check を追加する

共通の補助関数と check の集約は [tests/default.nix](../../tests/default.nix)、要素の検査は `tests/elements/<主な要素>.nix`、実在ホストの検査は [tests/hosts.nix](../../tests/hosts.nix) に置きます。要素のファイルは `{ lib, pkgs, system, helpers, ... }: { <名前> = <derivation>; }` の形でテストの attrset を返します。架空のホストは `tests/hosts/`、ユーザーは `tests/users/` に置きます。テスト用の設定ディレクトリは、実在と架空のホスト・ユーザー、および `config/elements/` を合わせて作られます。

各 check には次の札を1つ以上付けます。`check.sh` は札のない check の名前を表示して停止します。札の読み取りで未選択の構成まで評価しないよう、既存のテストと同じく `lib.lazyDerivation { derivation = <検査>; } // { <札>; }` で包みます。

- `elements = [ "要素名" ... ];`：生成結果を確かめる要素をすべて挙げます。影響する要素と重なればビルドします。例えば activation は `private_repos` と `secrets` です。シェルや Python を直接検査する場合も、そのファイルを読む要素を指定します。例えば windows-vm は `windows_vm` です。
- `hosts = [ "ホスト名" ... ];`：評価する実在ホストを挙げます。影響するホストと重なればビルドします。
- `always = true;`：読む要素のない graphify-smoke や proofread-howtouse などに使います。変更がある場合と `--all` / `--full` で、常にビルドします。

### 評価の範囲

軽量評価では、選択した NixOS ホストの assertions と `system.path` の drvPath、および選択した `homeConfigurations` の activation の drvPath を評価します。`--all` と `--full` は全ホストを選びます。このとき `system.build.toplevel` は評価されません。desktop や spin713 で全画面透過を行う mutter のパッチには `system.replaceDependencies` が使われており、toplevel の評価中にシステムクロージャの参照を生成する IFD（Import-From-Derivation）が発生してパッチ適用済み mutter のビルド待ちが生じるためです。`--full` を指定した場合は、先に全ホストの toplevel を評価してから `nix flake check --no-build --no-update-lock-file` を実行します（未生成の `references.nix.drv` に対して `nix flake check` を実行すると失敗するため）。なお、`--no-build` を指定してもこの評価依存は解消されません。全画面透過の見た目については、switch 後に実機上で目視確認してください。

[CI](../../.github/workflows/check.yml) は Linux runner 上で `--full` を実行します。キャッシュのない新規の CI 環境では、GUI や音楽制作関連を含む膨大なストア依存のダウンロードやビルドが発生するため、十分なディスク容量と実行時間が必要です。リモートでの CI 実行結果は、push 後にご確認ください。

Git flake は未追跡（untracked）ファイルを認識しません。新規ファイルは必ず `git add <path>`（差分をステージングしたくない場合は `git add -N <path>`）を実行してから検証してください。また、lock ファイルの更新作業は検証作業と切り離して扱います。

## 確認できないこと

本人のローカルチェックアウト環境や秘密鍵にはアクセスしないため、実際のネットワーク通信を伴う操作や実環境への適用は行いません。Darwin 構成は Linux 上でも評価自体は可能ですが、macOS 用バイナリのビルド、activation、GUI の動作までを検証したことにはなりません。また、外部リンクの到達性やドキュメント内容自体の正確性も、自動リンク検証の対象外です。

## 対象別の確認手順

パッケージ更新時は、リポジトリのルートで対象パッケージを単体ビルドし、installCheck まで実行します。
Happy の実行例:

```sh
nix build --impure --expr '(builtins.getFlake (toString ./.)).nixosConfigurations.nixos-desktop.pkgs.callPackage ./packages/happy { }'
```

上記の `happy` を `dpt-rp1-py` や `antigravity-cli` に置き換えることで、それぞれのパッケージ定義を確認できます。
overlay 適用済みの Graphify を確認する場合は以下を実行します。

```sh
nix build --impure --expr '(builtins.getFlake (toString ./.)).nixosConfigurations.nixos-desktop.pkgs.graphify'
```

各コマンドの動作確認は、ビルド結果として生成された `result/bin/<コマンド>` を使って行います。

- activation: dry-run の実行と、失敗後の再実行が可能かを確認します。実際の秘密鍵の復元やリポジトリの clone については、ユーザー自身が対象環境で確認してください。
- Neovim: Lua の構文チェックと対象機能の実機確認を行います。live checkout への変更は rebuild を待たずに即時反映されます。

Neovim における Markdown パーサー指定のマージ処理は、lazy.nvim 導入済みの Neovim を使用し、リポジトリのルートから確認します。プラグインのダウンロードやパーサーのビルドは不要です。

```sh
nvim --headless -n -u NONE -i NONE -l scripts/check-neovim-parser-merge.lua
```

[回帰チェック](../../scripts/check-neovim-parser-merge.lua) では、実際の lazy.nvim のマージ処理を利用し、共通 spec と Markdown spec の読み込み順を入れ替えても必要なパーサーが保持されることを確認します。背景の詳細は [spec マージの設計](../architecture/neovim/spec-merge.md) を参照してください。

構成の適用は、利用者自身が README に記載されたコマンドに従って実行し、実行結果や必要に応じた復旧手順を確認してください。

## 原因切り分け時の評価手順

`system.replaceDependencies` を使用している desktop や spin713 の `system.build.toplevel` は、評価を行うだけでもシステム全体の取得とビルド待ちが発生します。設定エラーや警告の有無を確認するだけであれば、依存置換を通らない属性値を優先して評価します。

```sh
h=nixos-desktop
nix eval --json .#nixosConfigurations.$h.config.assertions \
  --apply 'as: map (a: a.message) (builtins.filter (a: !a.assertion) as)'
nix eval --json .#nixosConfigurations.$h.config.warnings
nix eval --raw .#nixosConfigurations.$h.config.system.path.drvPath
nix eval --raw .#nixosConfigurations.$h.config.system.build.etc.drvPath
```

ただし、この切り分け用の評価では home-manager-files のようにビルド時に初めて発生するエラーは検出できず、devShells も対象外となります。最終的には冒頭の選択基準に従い、対象のビルドや check、または必要に応じて一括検証を行ってください。

リファクタリング時に挙動の変化がないことを確認する場合は、`config.system.path` のストアパスと、変更対象の値の評価結果を適用前後で比較します。前述のとおり `system.build.toplevel` は評価負荷が非常に重いため注意してください。なお、`nix-diff` は入力が変化した derivation の環境比較を省略する場合があるため、「差分が出なかったこと」だけをもって変更なしの根拠としないよう留意してください。
