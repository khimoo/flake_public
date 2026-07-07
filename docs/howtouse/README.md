# 使い方ガイド

この Flake で管理している環境の使い方ドキュメント。

## 目次

| カテゴリ | 概要 | ドキュメント |
|----------|------|-------------|
| ユーザー管理 | ユーザーの追加・権限設定・home-manager 連携 | [users.md](./users.md) |
| マシン間 SSH | flake 内のホストへ `ssh <短縮名>` で接続・マシン追加手順 | [machine-ssh.md](./machine-ssh.md) |
| リモートビルド | 別ホストでビルドだけ走らせて成果物を持ってくる運用 | [remote-build.md](./remote-build.md) |
| CLI ツール | シェル環境・ターミナル・ファイルマネージャ等 | [cli-tools/README.md](./cli-tools/README.md) |
| Neovim | プラグイン・キーバインド・ワークフロー | [modules/home-manager/dev/neovim/config/docs/README.md](../../modules/home-manager/dev/neovim/config/docs/README.md) |
| wezterm | ターミナルのキーバインド・ペイン・ワークスペース | [cli-tools/wezterm.md](./cli-tools/wezterm.md) |
| 共通 devShell | コードリーディング用 devShell を `.envrc` から参照する運用 | [devshells.md](./devshells.md) |
| papis ライブラリ同期 | papis ライブラリを Google Drive 経由で複数マシン同期する使い方・鍵運用 | [papis-gdrive-sync.md](./papis-gdrive-sync.md) |

## 関連

- 設計判断・実装方針は [docs/architecture/](../architecture/README.md) を参照
