# GUI アプリの管理

設計: [構成の境界](../architecture/configuration.md) / [デフォルトアプリ](../architecture/default-apps.md)
実装のエントリポイント: [gui/default.nix](../../modules/home-manager/gui/default.nix)

## 追加・削除の手順と場所

GUI 機能は、Linux 環境の個人用 home モジュールで `local.profile.features.gui = true` を設定して有効化します。なお、GNOME や IME は個別の機能フラグとして分離されており、WSLg 環境では GUI 機能のみを選択して利用します。

[gui/apps.nix](../../modules/home-manager/gui/apps.nix) の `guiApps` に登録されたアプリは、各エントリ内でパッケージの導入、Wayland 起動設定、自動起動、MIME タイプの関連付けを一元管理します。例えば、PDF の既定アプリは次のように定義します。

```nix
{ pkg = pkgs.pdfarranger; mimeTypes = { "application/pdf" = true; }; }
```

エントリを削除すると、そこから自動生成される設定もすべて削除されます。ただし、独立して定義されている外部設定への参照関係は別途確認してください。VS Code や IntelliJ などの開発用アプリは [dev/apps.nix](../../modules/home-manager/dev/apps.nix) で管理し、Firefox やターミナルエミュレータは専用のモジュールが担当します。また、Slack、Discord、Spotify、Zoom などの URL スキームも各エントリの `mimeTypes` 内で指定します。Obsidian の導入とスキーム登録については [memex.nix](../../modules/home-manager/memex.nix) で管理します。新しく GUI 子モジュールを追加・import する場合は、`gui/default.nix` に記述してください。
