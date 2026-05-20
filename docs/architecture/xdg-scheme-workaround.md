# XDG スキームハンドラ ワークアラウンド

設定ファイル: `modules/home-manager/gui/xdg-scheme-workaround.nix`

**このファイルは一時的なワークアラウンドであり、upstream の修正がマージされたら削除可能。**

## 問題

NixOS では、アプリの `.desktop` ファイルが `x-scheme-handler/slack` 等のカスタムプロトコルを `MimeType=` で宣言していても、GNOME の XDG portal は `mimeapps.list` に明示的なデフォルトエントリがないとスキームハンドラを解決できない。

これにより、ブラウザでの OAuth 認証後にアプリへリダイレクトされない（例: Slack ログイン後「Slack を開く」が機能しない）。

`xdg-mime query default x-scheme-handler/slack` が正しく `slack.desktop` を返していても、GNOME portal の解決パスが異なるため実際には動作しない。

## 影響を受けるアプリ

カスタム URL スキームでブラウザからアプリに遷移するすべてのアプリが対象:

- Slack (`slack://`)
- Discord (`discord://`)
- Obsidian (`obsidian://`)
- Zoom (`zoommtg://`, `zoomus://`)
- Spotify (`spotify://`)

## upstream の状況

- Issue: [NixOS/nixpkgs#301893](https://github.com/NixOS/nixpkgs/issues/301893)
- Fix: [NixOS/nixpkgs#494847](https://github.com/NixOS/nixpkgs/pull/494847) — スキームハンドラが1つしかない場合に自動でデフォルト登録する修正。`staging-nixos` ブランチ向けで、まだマージされていない。

## 削除手順

PR #494847 がマージされ、使用中の nixpkgs に含まれたら:

1. `modules/home-manager/gui/xdg-scheme-workaround.nix` を削除
2. `flake.nix` の `homeModules` からインポートを削除
3. Slack 等のブラウザ認証リダイレクトが動作することを確認

## 関連

- MIME 設定の全体像: [default-apps.md](./default-apps.md)
