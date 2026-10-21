# XDG スキームハンドラ ワークアラウンド

実装: [gui/apps.nix](../../modules/home-manager/gui/apps.nix) の `mimeTypes`、[zettelkasten.nix](../../modules/home-manager/zettelkasten.nix) の Obsidian 登録
使い方: [GUI アプリの管理](../howtouse/gui-apps.md)

アプリの導入条件と同じ条件で、URL スキームの既定を明示登録する。Slack・Discord・Spotify・Zoom は `guiApps` の項目を外せば登録も外れる。Obsidian は `obsidianOn` のときだけ登録する。Zoom の desktop ファイル名は `Zoom.desktop`。

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

## 見直す条件

PR #494847 がマージされ、使用中の nixpkgs に含まれたら:

Slack 等のブラウザ認証リダイレクトを確かめ、明示登録が不要なら各アプリのスキーム用 `mimeTypes` と Obsidian の登録を外す。ファイル用 MIME の既定は維持する。

## 関連

- MIME 設定の全体像: [default-apps.md](./default-apps.md)
