# GUI アプリの管理

設計: [構成の境界](../architecture/configuration.md) / [デフォルトアプリ](../architecture/default-apps.md)
実装の入口: [gui/default.nix](../../modules/home-manager/gui/default.nix)

## 追加・削除する場所

GUI は Linux の本人用 home モジュールで `local.profile.features.gui = true` を設定して使います。GNOME と IME は別の機能フラグです。WSLg は GUI だけを選択しています。

[gui/apps.nix](../../modules/home-manager/gui/apps.nix) の `guiApps` にあるアプリは、そのエントリで導入パッケージ、Wayland 起動設定、自動起動、MIME 関連付けを管理します。例えば PDF の既定アプリの定義は次の形です。

```nix
{ pkg = pkgs.pdfarranger; mimeTypes = { "application/pdf" = true; }; }
```

エントリを削除すると、そこから生成する設定もなくなります。ただし、独立した設定の参照は別途たどってください。VS Code・IntelliJ などの開発用アプリは [dev/apps.nix](../../modules/home-manager/dev/apps.nix)、Firefox や端末は専用モジュールが扱います。Slack・Discord・Spotify・Zoom のスキームも各エントリの `mimeTypes` に含めます。Obsidian の導入とスキーム登録は [zettelkasten.nix](../../modules/home-manager/zettelkasten.nix) が扱います。新しい GUI 子モジュールの import は `gui/default.nix` に追加します。

## Kiro・Cursor を導入していた環境

2026-10-20 に Kiro と Cursor の導入設定を削除しました。Kiro の flake input・専用依存、両アプリの起動項目、Cursor の AppImage の自動取得・更新処理を削除し、Cursor の起動に使っていた `appimage-run` の明示導入も外しました。

Kiro の input と、Kiro だけが使っていた依存を `flake.lock` から除きました。

変更の適用は利用者が行います。適用後に Kiro のパッケージと両アプリの管理対象の起動項目が外れていることを確認してください。この変更時点では評価・build・activation・実機確認を行っていません。

以前の Cursor の activation は、次のファイルを Home Manager の管理リンクではなく通常のファイルとして保存していました。今回の設定削除では自動削除しません。不要になった環境では、適用後に本人が削除できます。

```sh
rm -f -- "$HOME/.local/bin/cursor.AppImage" "$HOME/.local/share/icons/cursor.png"
```

アプリ自身が保存した設定・履歴・認証情報は、この手順では削除しません。今回の作業でも既存ホーム内のファイルは操作していません。
