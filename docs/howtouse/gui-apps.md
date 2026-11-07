# GUI アプリの管理

設計: [構成の境界](../architecture/configuration.md) / [デフォルトアプリ](../architecture/default-apps.md)
実装のエントリポイント: [gui.star](../../config/elements/gui.star)

## 追加・削除の手順と場所

GUI は、ホストの目的のファイル（`config/hosts/<ホスト>.star`）で目的 `gui` を選ぶと入ります（[confgen.md](./confgen.md)）。GNOME と IME は目的 `gnome`、`japanese_input` として分かれていて、WSLg の環境では `gui` だけを選んでいます。

[gui_apps.star](../../config/elements/gui_apps.star) の `_apps` に登録されたアプリは、各エントリ内でパッケージの導入、Wayland 起動設定、自動起動、MIME タイプの関連付けを一元管理します。例えば、PDF の既定アプリは次のように定義します。

```python
{"pkg": pkg("pdfarranger"), "desktop": "pdfarranger.desktop", "mime": ["application/pdf"]},
```

エントリを削除すると、そこから自動生成される設定もすべて削除されます。ただし、独立して定義されている外部設定への参照関係は別途確認してください。VS Code や IntelliJ などの開発用アプリは [dev_tools.star](../../config/elements/dev_tools.star) で管理し、Firefox やターミナルエミュレータは専用のモジュールが担当します。また、Slack、Discord、Spotify、Zoom などの URL スキームも各エントリの `mime` で指定します。.desktop の名前や実行ファイルの名前は Starlark から調べられないので、`desktop`、`bin`、`name` に書きます。Obsidian の導入とスキーム登録については要素 [memex.star](../../config/elements/memex.star) と [obsidian.star](../../config/elements/obsidian.star) で管理します。GUI の部品の要素を足すときは、`gui.star` の `requires` に挙げます。
