# Architecture

Flake 設定の設計判断・実装構造のドキュメント。設定変更時に参照する。

## 目次

| ドキュメント | 概要 |
|-------------|------|
| [default-apps.md](./default-apps.md) | デフォルトアプリケーションの MIME 関連付け設定 |
| [teams-dispatcher.md](./teams-dispatcher.md) | Teams マルチアカウント URL ディスパッチャ |
| [rustowl.md](./rustowl.md) | RustOwl の impure インストール |
| [users.md](./users.md) | ユーザー管理・sudo 設定・home-manager 連携 |
| [machine-ssh.md](./machine-ssh.md) | flake 内マシンの相互 SSH（`machines.nix` 集約・per-machine 鍵）の設計判断 |
| [remote-build.md](./remote-build.md) | SSH 経由のリモートビルド（`--build-host`）の設計判断 |
| [xdg-scheme-workaround.md](./xdg-scheme-workaround.md) | XDG スキームハンドラの手動登録（一時的） |
| [devshells.md](./devshells.md) | コードリーディング用共通 devShell の設計判断 |
| [zotero-gdrive-sync.md](./zotero-gdrive-sync.md) | Zotero PDF の Google Drive 同期（rclone bisync + sops）の設計判断 |
