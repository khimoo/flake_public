# Architecture

Flake 設定の設計判断・実装構造のドキュメント。設定変更時に参照する。各行は文書の目的だけを示し、判断の内容は各文書に書く。

## 目次

| ドキュメント | 概要 |
|-------------|------|
| [configuration.md](./configuration.md) | ホスト・個人プロファイル・オプションの境界と、目的別の選択 |
| [users.md](./users.md) | ユーザー管理と sudo、Home Manager との連携の設計 |
| [machine-ssh.md](./machine-ssh.md) | マシン間 SSH と LAN 共通鍵の設計 |
| [remote-build.md](./remote-build.md) | リモートビルドの設計 |
| [tailscale.md](./tailscale.md) | LAN の外からの SSH・リモートビルド・RDP の経路の設計 |
| [private-repo-clone.md](./private-repo-clone.md) | SSH 鍵の配布、秘密の更新、private repo の clone の設計 |
| [new-machine.md](./new-machine.md) | 新マシンのプロビジョニングの設計メモ（未実装） |
| [disk-tiering.md](./disk-tiering.md) | NVMe と SATA の 2 層ディスク構成の設計 |
| [kernel-pin.md](./kernel-pin.md) | デスクトップのカーネルの選び方 |
| [unstable-packages.md](./unstable-packages.md) | nixos-unstable から一部のパッケージだけを取る判断 |
| [wsl.md](./wsl.md) | 会社 PC の NixOS-WSL の設計 |
| [windows-vm.md](./windows-vm.md) | デスクトップの Windows VM の設計 |
| [gnome-transparent-fullscreen.md](./gnome-transparent-fullscreen.md) | 全画面の半透明ウィンドウを透かす mutter のパッチの判断 |
| [audio-echo-cancel.md](./audio-echo-cancel.md) | 通話用エコーキャンセルの設計 |
| [default-apps.md](./default-apps.md) | 既定アプリと URL スキームの関連付けの設計 |
| [xdg-scheme-workaround.md](./xdg-scheme-workaround.md) | URL スキームの既定を明示登録する理由 |
| [teams-dispatcher.md](./teams-dispatcher.md) | Teams のマルチアカウント用 URL ディスパッチャの設計 |
| [kitty.md](./kitty.md) | 端末を kitty にした判断とキー体系の設計 |
| [devshells.md](./devshells.md) | コードリーディング用の共通 devShell の設計 |
| [mimikopi-env.md](./mimikopi-env.md) | 耳コピの ML モデルを動かす環境の設計 |
| [neovim/plugin-manager.md](./neovim/plugin-manager.md) | Neovim のプラグインを lazy.nvim で管理し、単独では公開しない判断 |
| [neovim/features.md](./neovim/features.md) | Neovim のプラグインと外部の道具を機能として組にする仕組み |
| [neovim/spec-merge.md](./neovim/spec-merge.md) | Neovim の言語ごとの設定を spec のマージで足す設計 |
| [rustowl.md](./rustowl.md) | RustOwl の導入と Neovim 連携の設計 |
| [agent-config.md](./agent-config.md) | Claude Code と Codex のユーザー設定の管理の設計 |
| [codex-subagents.md](./codex-subagents.md) | Codex のサブエージェントを無効化する判断 |
| [llm-wikis.md](./llm-wikis.md) | LLM Wiki を独立した private repo に置く判断 |
| [papis-gdrive-sync.md](./papis-gdrive-sync.md) | 文献管理に papis を選び vault 内に置く判断 |
| [zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md) | vault の添付と papis ライブラリの Drive 同期の設計 |
| [zettelkasten-vault-skeleton.md](./zettelkasten-vault-skeleton.md) | vault の骨格の配布とミラーの設計 |
| [minecraft-backup.md](./minecraft-backup.md) | Minecraft のインスタンスのバックアップの設計 |
| [quaderno.md](./quaderno.md) | Quaderno からの手書き PDF の取り込みの設計 |
| [x-likes.md](./x-likes.md) | X のいいねの保存と意味検索の実行環境、データベース、定期実行の設計 |

小さな機能（agy、comma、Graphify、Inkscape、uv-mode）は、使い方の文書の「設計」の節に判断を書く（[使い方ガイド](../howtouse/README.md)）。
