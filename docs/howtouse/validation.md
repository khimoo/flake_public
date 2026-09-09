# 変更の検証

設計: [構成の境界](../architecture/configuration.md)
実装: [check.sh](../../scripts/check.sh) / [モジュール検証](../../tests/default.nix) / [文書検証](../../scripts/check-docs.py)

## 一括検証

Nix（flakes有効）、Python 3、Git、Bashが必要です。

```sh
bash scripts/check.sh
```

1. MarkdownのローカルファイルリンクとAI共通規約の入口を確認。
2. 両ホストの `system.build.toplevel.drvPath` を明示評価してから、`nix flake check --no-build --no-update-lock-file` でNixOS両ホスト・native packages・devShells・checksを評価。
3. `homeConfigurations` の全 `activationPackage.drvPath` を明示的に評価。
4. Linux / Darwinのモジュール検証を評価し、nativeのchecks（モジュール・文書・隔離したactivationテスト）だけをbuild。
5. `git diff --check` で空白の問題を確認。

[CI](../../.github/workflows/check.yml) もLinux runnerで同じコマンドを使います。リモートのCI実行はpush後に確認してください。

Git flakeは未追跡ファイルを読みません。新しいファイルは `git add <path>`（差分をstageしたくなければ `git add -N <path>`）してから検証します。lock更新は検証に混ぜません。

## 確認できること・できないこと

ユーザー分離、型・必須パス、未対応OSの機能拒否、CLI構成にGUI開発アプリが入らないことを確認します。activationテストは生成されたスクリプトのパスを一時領域と偽のGit/Sopsへ置換し、dry-run、clone・鍵復号の失敗と再実行を確認します。本人のcheckout・秘密鍵にはアクセスせず、実際のネットワーク操作や環境適用は行いません。

Darwin構成はLinuxから評価できますが、macOSバイナリのbuild・activation・GUI動作を検証したことにはなりません。外部リンクの到達性、Markdownの見出しanchor、文書内容の正しさも自動リンク検証の対象外です。

spin713の音声回避策は `system.replaceDependencies` を使い、評価中にシステムclosureの参照を生成するimport-from-derivation（IFD）が発生します。未生成の `references.nix.drv` に対して `nix flake check` が失敗するため、一括検証では先に両ホストを明示評価します。freshなCIではGUI・音楽制作を含む多数のstore依存を取得・buildするので、十分なディスク容量と時間が必要です。`--no-build` はこの評価依存をなくす指定ではありません。NixOSの世代切替は行いません。

## 変更に応じた追加確認

- パッケージ: `nix build --no-link .#happy` などで変更したパッケージのinstallCheckまで実行。
- activation: dry-runと失敗後の再実行を確認。実際の鍵復元・cloneはユーザーが対象環境で確認。
- Neovim: Luaの構文と対象機能を実機で確認。live checkoutの変更はrebuildを待たず反映されます。
- 文書だけ: `python3 scripts/check-docs.py .` と `git diff --check`。

適用は利用者自身がREADMEのコマンドで行い、結果と必要なら復旧手順を確認します。
