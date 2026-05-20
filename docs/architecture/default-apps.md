# デフォルトアプリケーション設定

## 概要

MIME タイプに対するデフォルトアプリケーションは `xdg.mimeApps.defaultApplications` で管理している。
設定は複数モジュールに分散しており、home-manager のモジュールシステムが最終的にマージする。

## 設定箇所

| 対象 MIME | 設定ファイル | 方式 |
|-----------|-------------|------|
| PDF, 画像, 動画, 音声, メール等 | [gui/apps.nix](gui/apps.nix) | `guiApps` の `mimeTypes` 属性から導出 |
| text/html, text/xml, about 等 | `gui/firefox.nix` | `programs.firefox` + 直接指定 |
| HTTP/HTTPS | `gui/teams-dispatcher.nix` | Teams URL ディスパッチャ経由 |
| カスタムスキーム (slack://, discord:// 等) | `gui/xdg-scheme-workaround.nix` | NixOS の XDG 問題のワークアラウンド ([詳細](./xdg-scheme-workaround.md)) |

パスはすべて `modules/home-manager/` からの相対。

## 設定方式の使い分け

| アプリの種類 | 方式 | MIME 設定方法 |
|-------------|------|-------------|
| シンプルなアプリ | `gui/apps.nix` の `guiApps` リスト | `mimeTypes` 属性から導出 |
| `programs.*` で細かく設定するアプリ | 専用ファイル（例: `gui/firefox.nix`） | ファイル内で直接 `xdg.mimeApps.defaultApplications` を設定 |

どちらの方式で書いても、モジュールシステムが最終的に一つの `mimeapps.list` にマージする。

## apps.nix の仕組み

各アプリ定義に `mimeTypes` 属性を持たせ、`foldl'` で `defaultApplications` attrset を導出する。
アプリを `guiApps` から削除すると MIME 設定も自動的に消える。

```nix
# アプリ定義
{ pkg = pkgs.pdfarranger; mimeTypes = { "application/pdf" = true; }; }

# 導出（getDesktopName で .desktop ファイル名を解決）
defaultApplications = lib.foldl' (acc: app:
  if app ? mimeTypes then
    acc // (lib.mapAttrs (_: _: getDesktopName app) app.mimeTypes)
  else acc
) {} guiApps;
```

同一 MIME を複数アプリに設定した場合、リスト後方のアプリが優先される（`//` の挙動）。

## Firefox

- **インストール + 設定**: `gui/firefox.nix` の `programs.firefox.enable = true`（home-manager モジュール）
- **MIME 設定**: 同ファイル内で `text/html` 等を直接設定
- **HTTP/HTTPS**: `teams-dispatcher.nix` がディスパッチャ経由で制御（Firefox に直接割り当てない）
- 将来 `programs.firefox.profiles` でプロファイル・拡張機能等を宣言的に管理可能

## 変更ガイド

| やりたいこと | 変更箇所 |
|-------------|---------|
| 一般アプリのデフォルトを追加・変更 | `apps.nix` の該当アプリに `mimeTypes` を設定 |
| Firefox の MIME を変更 | `firefox.nix` の `defaultApplications` |
| Firefox の内部設定を追加 | `firefox.nix` の `programs.firefox` |
| デフォルトブラウザ自体を変更 | `firefox.nix` と `teams-dispatcher.nix` の両方 |
| 新しい MIME タイプを追加 | `apps.nix` の該当アプリの `mimeTypes` に追記 |
