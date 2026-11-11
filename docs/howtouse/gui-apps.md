# GUI アプリの管理

設計: [構成の境界](../architecture/configuration.md) / [デフォルトアプリ](../architecture/default-apps.md)
実装のエントリポイント: [gui_apps.star](../../config/elements/gui_apps.star) / [web_browsing.star](../../config/elements/web_browsing.star)

## 追加・削除の手順と場所

アプリは目的ごとに選びます。ホストのファイル（`config/hosts/<ホスト>.toml`）の `purposes` に、`web_browsing`（Zen を既定ブラウザにし、Firefox も残す）、`gui_apps`（下の一覧のアプリ）、`inkscape`、`teams_dispatcher` を挙げます（[confgen.md](./confgen.md)）。アプリの要素は土台の [gui.star](../../config/elements/gui.star)（kitty とフォント）を `requires` に挙げているので、目的から依存をたどって `gui` も入ります。アプリを入れずに kitty だけを使うホストは `gui` を選びます。GNOME と IME は目的 `gnome`、`japanese_input` として分かれています。

[gui_apps.star](../../config/elements/gui_apps.star) の `_apps` に登録されたアプリは、各エントリ内でパッケージの導入、Wayland 起動設定、自動起動、MIME タイプの関連付けを一元管理します。例えば、PDF の既定アプリは次のように定義します。

```python
{"pkg": pkg("pdfarranger"), "desktop": "pdfarranger.desktop", "mime": ["application/pdf"]},
```

エントリを削除すると、そこから自動生成される設定もすべて削除されます。ただし、独立して定義されている外部設定への参照関係は別途確認してください。VS Code や IntelliJ などの開発用アプリは [dev_tools.star](../../config/elements/dev_tools.star) で管理し、Firefox やターミナルエミュレータは専用のモジュールが担当します。また、Slack、Discord、Spotify、Zoom などの URL スキームも各エントリの `mime` で指定します。.desktop の名前や実行ファイルの名前は Starlark から調べられないので、`desktop`、`bin`、`name` に書きます。Obsidian の導入とスキーム登録については要素 [memex.star](../../config/elements/memex.star) と [obsidian.star](../../config/elements/obsidian.star) で管理します。GUI アプリの要素を足すときは、その要素の `requires` に `gui` を挙げ、使うホストの `purposes` で選びます。

## 既定ブラウザの変更と更新

[web_browsing.star](../../config/elements/web_browsing.star) の `public` と `config` が受け取るブラウザを変更します。Zen を選ぶ場合は `zen_browser`、Firefox に戻す場合は `firefox` にし、各関数内の参照も同じ名前に変えます。通常のリンクと HTML の関連付けが一緒に変わり、Teams のリンクは引き続き Junction へ渡されます。

Zen 本体は [zen_browser.star](../../config/elements/zen_browser.star) で導入します。[zen-browser-flake](https://github.com/0xc000022070/zen-browser-flake) の Beta パッケージを使い、バージョンは `flake.lock` で固定しています。更新は `nix flake update zen-browser` を実行し、[検証ガイド](validation.md) に従って確認します。設定の反映方法は [README](../../README.md) を参照してください。

Firefox のデータはそのまま残ります。ブックマークやログイン情報の Zen への移行は、利用者が Zen のインポート機能で行います。

## GNOME 拡張の切り替えと設定

GNOME のアプリ一覧で「拡張機能」を開くか、端末から `gnome-extensions-app` を実行します。GNOME 同梱の管理画面で、導入済みの拡張のオン・オフと設定を変更できます。

拡張の追加・削除は [gnome.star](../../config/elements/gnome.star) の `home.packages` と `enabled-extensions` を変更し、設定を反映します。管理画面で切り替えた有効状態は、設定を再び反映すると `enabled-extensions` の指定に戻る場合があります。
