対象ツール: $ARGUMENTS

[共通規約](../../AGENTS.md) の Documentation / Verification に従って、対象の使い方と設計文書を整備する。

1. 設定ファイル、既存の使い方・設計文書、各目次を読む。
2. 有効化条件、対応OS、キーバインド、設定変更・復旧手順を実装と照合する。
3. 使い方は `docs/howtouse/`、設計理由は `docs/architecture/` に配置する。Neovim固有だけは `modules/home-manager/dev/neovim/config/docs/` を使う。
4. 対になる文書と実装へのリンクを入れ、追加・削除した場合は目次も更新する。表の詳細を複数の目次に複写しない。
5. `python3 scripts/check-docs.py .` と `git diff --check` を実行する。設定も変更した場合は `bash scripts/check.sh` を実行する。
6. 変更内容、確認結果、未検証事項を報告する。

このコマンドの明示的な実行は文書編集の依頼として扱う。別の設定変更が必要になったら、ユーザーが既に依頼した範囲か判断する。リポジトリ外のメモリを規約や目次の正本にしない。
