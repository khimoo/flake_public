# デフォルトアプリケーション設定

使い方: [GUI アプリの管理](../howtouse/gui-apps.md)

## 概要

MIME タイプに対するデフォルトアプリケーションは `xdg.mimeApps.defaultApplications` で管理している。
設定は複数モジュールに分散しており、home-manager のモジュールシステムが最終的にマージする。

## 設定箇所

| 対象 MIME | 設定ファイル | 方式 |
|-----------|-------------|------|
| PDF, 画像, 動画, 音声, メール等 | [gui/apps.nix](../../modules/home-manager/gui/apps.nix) | `guiApps` の `mimeTypes` 属性から導出 |
| text/html, text/xml, about 等 | `gui/firefox.nix` | `programs.firefox` + 直接指定 |
| HTTP/HTTPS | `gui/teams-dispatcher.nix` | Teams URL ディスパッチャ経由 |
| Slack・Discord・Spotify・Zoom のスキーム | `gui/apps.nix` | アプリごとの `mimeTypes` から導出（[理由](./xdg-scheme-workaround.md)） |
| Obsidian のスキーム | `zettelkasten.nix` | Obsidian 有効時だけ登録 |

パスはすべて `modules/home-manager/` からの相対。

## 設定方式の使い分け

| アプリの種類 | 方式 | MIME 設定方法 |
|-------------|------|-------------|
| シンプルなアプリ | `gui/apps.nix` の `guiApps` リスト | `mimeTypes` 属性から導出 |
| `programs.*` で細かく設定するアプリ | 専用ファイル（例: `gui/firefox.nix`） | ファイル内で直接 `xdg.mimeApps.defaultApplications` を設定 |

どちらの方式で書いても、モジュールシステムが最終的に一つの `mimeapps.list` にマージする。

## apps.nix の仕組み

各アプリの定義に `mimeTypes` を持たせ、そこから `defaultApplications` を作る。アプリを `guiApps` から消すと、MIME の設定も一緒に消える。
同じ MIME を複数のアプリに設定すると、リストの後ろのアプリが優先される（`//` で重ねるため）。

## Firefox

- **インストール + 設定**: `gui/firefox.nix` の `programs.firefox.enable = true`（home-manager モジュール）
- **MIME 設定**: 同ファイル内で `text/html` 等を直接設定
- **HTTP/HTTPS**: `teams-dispatcher.nix` がディスパッチャ経由で制御（Firefox に直接割り当てない）

## 変更ガイド

| やりたいこと | 変更箇所 |
|-------------|---------|
| 一般アプリのデフォルトを追加・変更 | `apps.nix` の該当アプリに `mimeTypes` を設定 |
| Firefox の MIME を変更 | `firefox.nix` の `defaultApplications` |
| Firefox の内部設定を追加 | `firefox.nix` の `programs.firefox` |
| デフォルトブラウザ自体を変更 | `firefox.nix` と `teams-dispatcher.nix` の両方 |
| 新しい MIME タイプを追加 | `apps.nix` の該当アプリの `mimeTypes` に追記 |
