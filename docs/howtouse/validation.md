# 変更の検証

設計: [構成の境界](../architecture/configuration.md)
実装: [check.sh](../../scripts/check.sh) / [モジュール検証](../../tests/default.nix) / [文書検証](../../scripts/check-docs.py)

## 変更範囲から検証を選ぶ

変更した境界を確認できる最小の検証を選びます。一括検証を毎回の既定にはしません。

| 変更範囲 | 選ぶ検証 |
|---|---|
| 文書のみ | `python3 scripts/check-docs.py .` と `git diff --check` |
| パッケージ | 変更したパッケージを build し、既存の installCheck まで確認 |
| ホスト・Home Manager モジュール | 対象構成を評価し、該当する check または変更パッケージを build |
| エディタ | 対象設定・Lua などの構文と、対象機能の実機確認 |
| 影響を特定の出力に限定できない変更 | 下記の一括検証 |

構成の組み立て、ユーザー分離、共通の OS 条件、activation 基盤、全体に効く overlay などの変更では、影響範囲を確認して一括検証を選びます。第二の構成へ確認を広げるのは、共有経路の変更で必要な場合です。回帰には壊れた契約を確認する既存の check を拡張するか、対象を絞った確認を追加し、実装の文面をなぞるだけのテストや新しい評価基盤を安易に増やしません。

重い評価・build はデスクトップで行い、`nixos-spin713` で全体検証を実行しません。ユーザーが検証省略を指定した場合は従い、未検証と報告します。文書整備の進め方は [文書整備](documentation.md) を参照してください。

## 一括検証

Nix（flakes有効）、Python 3、Git、Bashが必要です。

```sh
bash scripts/check.sh
```

1. MarkdownのローカルファイルリンクとAI共通規約の入口を確認。
2. 全NixOSホストの `system.build.toplevel.drvPath` を明示評価してから、`nix flake check --no-build --no-update-lock-file` で全NixOSホスト・native packages・devShells・checksを評価。
3. `homeConfigurations` の全 `activationPackage.drvPath` を明示的に評価。
4. Linux / Darwinのモジュール検証を評価し、nativeのchecks（モジュール・GNOMEの拡張の対応版・private repoを持たないユーザーのpull-repos・文書・隔離したactivationテスト・Quadernoの選別ロジック・偽ホストに対する `cargo remote-run`・偽の virsh と FreeRDP に対する Windows VM のランチャーとそのビルド・デスクトップの keyd の設定の `keyd check`）だけをbuild。
5. `git diff --check` で空白の問題を確認。

[CI](../../.github/workflows/check.yml) もLinux runnerで同じコマンドを使います。リモートのCI実行はpush後に確認してください。

Git flakeは未追跡ファイルを読みません。新しいファイルは `git add <path>`（差分をstageしたくなければ `git add -N <path>`）してから検証します。lock更新は検証に混ぜません。

## 確認できること・できないこと

ユーザー分離、型・必須パス、未対応OSの機能拒否、CLI構成にGUI開発アプリが入らないことを確認します。activationテストは生成されたスクリプトのパスを一時領域と偽のGit/Sopsへ置換し、dry-run、clone・鍵復号の失敗と再実行を確認します。本人のcheckout・秘密鍵にはアクセスせず、実際のネットワーク操作や環境適用は行いません。

Darwin構成はLinuxから評価できますが、macOSバイナリのbuild・activation・GUI動作を検証したことにはなりません。外部リンクの到達性、Markdownの見出しanchor、文書内容の正しさも自動リンク検証の対象外です。

spin713の音声回避策と、desktopとspin713の全画面を透かすmutterのパッチは `system.replaceDependencies` を使い、評価中にシステムclosureの参照を生成するimport-from-derivation（IFD）が発生します。評価の途中でパッチを当てたmutterもビルドするので、binary cacheに無い間はCIでもmutterのビルドを待ちます。未生成の `references.nix.drv` に対して `nix flake check` が失敗するため、一括検証では先に全NixOSホストを明示評価します。freshなCIではGUI・音楽制作を含む多数のstore依存を取得・buildするので、十分なディスク容量と時間が必要です。`--no-build` はこの評価依存をなくす指定ではありません。NixOSの世代切替は行いません。

## 対象別の確認手順

- パッケージ: `nix build --no-link .#happy` などで変更したパッケージのinstallCheckまで実行。
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
