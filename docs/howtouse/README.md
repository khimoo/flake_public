# 使い方ガイド

この Flake で管理している環境の使い方ドキュメント。各行は文書の目的だけを示す。

## 目次

| カテゴリ | 概要 | ドキュメント |
|----------|------|-------------|
| 文書整備 | 使い方・設計文書と索引を整える手順 | [documentation.md](./documentation.md) |
| 検証 | 変更範囲に応じた検証の選び方と `check.sh` | [validation.md](./validation.md) |
| ユーザー管理 | ユーザーの追加と権限、目的別の利用ユーザー | [users.md](./users.md) |
| SSH 鍵と private repo | 鍵の配布と更新、private repo の clone と更新 | [private-repo-clone.md](./private-repo-clone.md) |
| マシン間 SSH | マシン間の接続とマシンの追加・廃棄 | [machine-ssh.md](./machine-ssh.md) |
| リモートビルド | ビルドをデスクトップに回す方法 | [remote-build.md](./remote-build.md) |
| Tailscale | LAN の外からデスクトップを使う方法 | [tailscale.md](./tailscale.md) |
| 会社PCの NixOS-WSL | 会社 PC の WSL の導入と運用 | [wsl.md](./wsl.md) |
| ディスク階層構成 | 2 層ディスクの subvol とマウント | [disk-tiering.md](./disk-tiering.md) |
| GUI アプリ | GUI アプリの追加・削除の変更箇所 | [gui-apps.md](./gui-apps.md) |
| 定期実行の失敗の通知 | ユーザーの定期実行が失敗したときの通知と確認 | [failure-notify.md](./failure-notify.md) |
| デスクトップの Windows VM | Windows VM の起動と操作 | [windows-vm.md](./windows-vm.md) |
| 音声 | 通話用エコーキャンセルの選択と確認 | [audio-echo-cancel.md](./audio-echo-cancel.md) |
| CLI ツール | シェル環境と CLI ツール | [cli-tools/README.md](./cli-tools/README.md) |
| kitty | 端末の操作 | [cli-tools/kitty.md](./cli-tools/kitty.md) |
| Neovim | Neovim のプラグインとキー操作 | [neovim/README.md](./neovim/README.md) |
| キーボードのレイヤー | キーの割り当てを調べる手順 | [keyboard-layers.md](./keyboard-layers.md) |
| 共通 devShell | 共通 devShell をプロジェクトから使う方法 | [devshells.md](./devshells.md) |
| Inkscape | 新規文書の既定の色の管理 | [inkscape.md](./inkscape.md) |
| Graphify | コードと文書の探索 | [graphify.md](./graphify.md) |
| エージェント設定（Claude Code / Codex） | エージェントの設定の管理と変更 | [agent-config.md](./agent-config.md) |
| Codex のサブエージェント設定 | サブエージェントの無効化の確認と復帰 | [codex-subagents.md](./codex-subagents.md) |
| LLM Wiki | LLM Wiki の運用 | [llm-wikis.md](./llm-wikis.md) |
| papis の使い方 | 文献の追加と書き出し | [papis-gdrive-sync.md](./papis-gdrive-sync.md) |
| memex の Drive 同期 | 添付と papis ライブラリの同期の設定と運用 | [memex-attachments-sync.md](./memex-attachments-sync.md) |
| vault 骨格の配布・ミラー | vault の骨格を公開 repo へ写す手順 | [memex-vault-skeleton.md](./memex-vault-skeleton.md) |
| Minecraft バックアップ | インスタンスのバックアップと復元 | [minecraft-backup.md](./minecraft-backup.md) |
| Quaderno の取り込み | 手書き PDF の取り込み | [quaderno.md](./quaderno.md) |
| X のいいねとブックマークの保存 | いいねとブックマークの保存と意味検索、定期実行 | [xsaved.md](./xsaved.md) |

## 関連

- 設計判断・実装方針は [docs/architecture/](../architecture/README.md) を参照
