# GUI アプリの管理

設計: [構成の境界](../architecture/configuration.md) / [デフォルトアプリ](../architecture/default-apps.md)
実装のエントリポイント: [gui_apps.star](../../config/elements/gui_apps.star) / [web_browsing.star](../../config/elements/web_browsing.star)

## 追加・削除の手順と場所

アプリはユーザーの利用目的ごとに選びます。ホストのファイル（`config/hosts/<ホスト>.toml`）のユーザーの `[[users]]` の `purposes` に、`web_procedures`（`requires` の `web_browsing` が Zen を既定ブラウザにし、Firefox、Brave、Google Chrome も入れる）、`draw`（`requires` の `inkscape`）、`work_ss`（`requires` の `teams_dispatcher`）などを挙げます（[confgen.md](./confgen.md)）。無効にするにはユーザーの `purposes` から対応する利用目的を外します。kitty とフォントは [gui.star](../../config/elements/gui.star) が担当します。`gui`、`desktop`、`japanese_input` はハードウェアプロファイルの `requires` で選び、無効にする場合もハードウェアプロファイルの `requires` から外します。

`gui_apps` は `purposes` で選びません。アプリを使うコンポーネントの `writes(gui_apps)` が `write(gui_apps, pkg = ..., ...)` を返し、[gui_apps.star](../../config/elements/gui_apps.star) が受け取ったアプリのパッケージ、Wayland 起動設定、自動起動、MIME タイプの関連付けをまとめて生成します。アプリを追加・削除するときは、アプリを使うコンポーネントの `writes` を変更します。受け付ける引数と組み合わせの制約は、[gui_apps.star](../../config/elements/gui_apps.star) の `accept` に書かれています。例えば、PDF の既定アプリは [read_materials.star](../../config/elements/read_materials.star) で次のように定義します。

```python
def writes(gui_apps):
    return [
        write(gui_apps, pkg = pkg("pdfarranger"), desktop = "pdfarranger.desktop", mime = ["application/pdf"]),
    ]
```

エントリを削除すると、エントリから自動生成される設定もすべて削除されます。ただし、独立して定義されている外部設定への参照関係は別途確認してください。IntelliJ などの開発用アプリは [dev_tools_gui.star](../../config/elements/dev_tools_gui.star) で管理し、Firefox やターミナルエミュレータは専用のモジュールが担当します。また、Slack、Discord、Spotify、Zoom などの URL スキームも各エントリの `mime` で指定します。.desktop の名前や実行ファイルの名前は Starlark から調べられないので、`desktop`、`bin`、`name` に書きます。Wayland 起動と自動起動は、それぞれ `wayland = True` と `autostart = True` で指定します。Obsidian の導入とスキーム登録についてはコンポーネント [memex.star](../../config/elements/memex.star) と [obsidian.star](../../config/elements/obsidian.star) で管理します。パッケージと上の生成設定だけで足りるアプリは、`gui_apps` に寄与するだけのコンポーネントにします（例: [slack.star](../../config/elements/slack.star)、[zoom.star](../../config/elements/zoom.star)）。それ以外の設定も持つ GUI アプリのコンポーネント（例: [inkscape.star](../../config/elements/inkscape.star)、[obs.star](../../config/elements/obs.star)）は、`requires` に `gui` を挙げます。どちらも、アプリを使う利用目的のコンポーネントの `requires` から参照します。

## 既定ブラウザの変更と更新

[web_browsing.star](../../config/elements/web_browsing.star) の `public` と `config` が受け取るブラウザを変更します。Zen を選ぶ場合は `zen_browser`、Firefox に戻す場合は `firefox` にし、各関数内の参照も同じ名前に変えます。通常のリンクと HTML の関連付けが一緒に変わり、Teams のリンクは引き続き Junction へ渡されます。

Zen 本体は [zen_browser.star](../../config/elements/zen_browser.star) で、[zen-browser-flake](https://github.com/0xc000022070/zen-browser-flake) の Home Manager モジュールを使って導入します。Beta 版を使い、バージョンは `flake.lock` で固定しています。更新は `nix flake update zen-browser` を実行し、[検証ガイド](validation.md) に従って確認します。設定の反映方法は [README](../../README.md) を参照してください。

Firefox と Zen の拡張機能、pref、同期の分担は [ブラウザ](./browsers.md) にまとめています。

## デスクトップの設定

Niri のキー操作、Waybar、通知、ランチャーの変更と反映方法は [Niri](niri.md) を参照してください。ウィンドウの配置ルールは [niri_background_apps.star](../../config/elements/niri_background_apps.star) で管理します。

`autostart = True` のアプリは `~/.config/autostart/` に配置され、Niri が起動する `xdg-desktop-autostart.target` でセッション開始時に 1 回だけ起動します（`nixos-rebuild switch` 時の再起動対象にはなりません）。変更した自動起動の動作は再ログインで確認します。
