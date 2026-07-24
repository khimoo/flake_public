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
| [papis-gdrive-sync.md](./papis-gdrive-sync.md) | papis ライブラリの Google Drive 同期（workflow flake で仕組みを所有・rclone bisync + sops）の設計判断 |
| [zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md) | Obsidian vault 添付の Google Drive 同期（workflow flake で仕組みを所有・secret 共有）の設計判断 |
| [zettelkasten-obsidian-config.md](./zettelkasten-obsidian-config.md) | `.obsidian` 設定の配布（seed = public→vault）とミラー（mirror = vault→public の派生更新）。live source-of-truth は vault（obsidian-git）、public は派生スナップショットとして分離維持する設計判断 |
| [disk-tiering.md](./disk-tiering.md) | NVMe/SATA の 2 層ディスク構成（btrfs subvol・NOCOW・ブートメニュー）の設計判断 |
| [claude-config.md](./claude-config.md) | Claude Code ユーザー設定の git 管理（パス注入 + out-of-store symlink、flake input を退けた理由） |
| [private-repo-clone.md](./private-repo-clone.md) | private repo の宣言的 clone（home-manager の home.activation で age 鍵 1 本から SSH 鍵を復号し clone・NixOS/WSL/macOS 共通・zettelkasten の public 分割で eval 時の鍵依存は解消） |
