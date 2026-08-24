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
| papis の使い方 | 文献の追加・citekey の pin・BibTeX 書き出しと、papis 固有の同期上の注意 | [papis-gdrive-sync.md](./papis-gdrive-sync.md) |
| Zettelkasten の Drive 同期 | 添付と papis ライブラリの Google Drive 同期。新マシンのセットアップ（rclone 認証・初回同期）と日常運用 | [zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md) |
| vault 骨格の配布・ミラー | 分類フォルダ・運用ドキュメント・`.obsidian` を public repo へ写す（mirror）手順、何が公開され何が落ちるか、seed が自分のマシンでは動かない理由 | [zettelkasten-vault-skeleton.md](./zettelkasten-vault-skeleton.md) |
| ディスク階層構成 | NVMe(ホット)/SATA(コールド)の 2 層・btrfs subvol のレイアウトとセットアップ | [disk-tiering.md](./disk-tiering.md) |
| 写真の仕分け | Google Photos から引き上げた Takeout アーカイブを digiKam で選別する。原本の位置・展開手順・日付が当てにならない理由 | [photo-triage.md](./photo-triage.md) |
| Minecraft バックアップ | インスタンス終了で restic に世代を積み Drive へ写す。フック設定・復元手順・別マシンとの往復 | [minecraft-backup.md](./minecraft-backup.md) |
| Claude Code 設定 | グローバル CLAUDE.md・skills を private repo で git 管理し symlink で挿す運用 | [claude-config.md](./claude-config.md) |
| LLM Wiki | AI に読ませる知識ベースをドメインごとに育てる運用。ingest / query / lint の回し方、新ドメインの足し方 | [llm-wikis.md](./llm-wikis.md) |
| SSH 鍵配布と private repo 自動 clone | SSH 鍵（id_github / id_lan）を sops 暗号化し、age 鍵 1 本で新環境（NixOS/WSL/macOS）が switch 一発で鍵設置＋clone する運用 | [private-repo-clone.md](./private-repo-clone.md) |

## 関連

- 設計判断・実装方針は [docs/architecture/](../architecture/README.md) を参照
