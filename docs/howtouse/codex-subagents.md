# Codex のサブエージェント

Codex CLI のサブエージェント（`spawn_agent` などのマルチエージェントツール）は、全マシン共通で無効化されています。
NixOS では [modules/nixos/codex.nix](../../modules/nixos/codex.nix) によって `/etc/codex/config.toml` にその設定が書き込まれます。
例外として、`codex-astra` は agents-private の `codex/astra.config.toml` で `multi_agent_v2 = true` に設定し、sol-handoff の `sol-worker` を spawn できるようにしています（詳細は [agent-config.md](./agent-config.md) を参照）。

設計：[Codex のサブエージェントの設計](../architecture/codex-subagents.md)

## NixOS 以外（macOS）で無効化する手順

home-manager のみの構成では `/etc` を管理できないため、`~/.codex/config.toml` に手動で記述します。

```toml
[agents]
enabled = false

[features]
multi_agent_v2 = false
```

必ず両方の項目を記述してください。`features.multi_agent_v2` が有効になっていると `agents.enabled` より優先されるため、`[agents]` のみではモデル側の指定によって v2 が有効に戻ってしまうことがあります。
Codex はこのファイルを `toml_edit` で部分的に書き換えるため、コメントを残すことも可能です。ただし、設定値の記法が正規化される場合があります（例：`multi_agent_v2 = false` が `[features.multi_agent_v2]` テーブルと `enabled = false` に展開されるなど）。

## 無効化されているか確認する

どちらの確認コマンドも API は呼び出しません。

```sh
codex features list | grep multi_agent_v2    # false と表示されれば無効
codex debug prompt-input | grep spawn_agent  # 何も表示されなければ無効
```

`codex debug prompt-input` は、モデルに送信するプロンプトを JSON 形式で出力します。サブエージェントが有効な場合、`spawn_agent` の使い方を説明する developer メッセージが含まれます。
件数をカウントする際に `grep -c` を使用しないでください。`grep` が ripgrep（rg）の場合、一致件数が 0 件だと何も出力せず終了コード 1 で終了します。

```sh
codex debug prompt-input | python3 -c 'import sys; print(sys.stdin.read().count("spawn_agent"))'
```

## 有効に戻す手順

NixOS の場合は `modules/nixos/codex.nix` 内の `enabled` を `true` に変更して switch を実行します。それ以外の環境では `~/.codex/config.toml` の該当行を削除します。

有効に戻したうえでトークン消費量を抑えたい場合は、`spawn_agent` の `fork_turns` パラメータを指定させます。

- `"all"`（指定を省略した場合のデフォルト）：親の会話履歴をすべてコピーします。
- `"3"` などの正の整数の文字列：直近の N ターンのみを渡します。
- `"none"`：会話履歴を渡さず、役割の指示とタスク内容のみを渡します。

`fork_turns` は全体設定のキーではなく `spawn_agent` ツールの引数であるため、デフォルト値を設定ファイルで一括指定することはできません。そのため、`AGENTS.md` に明記するか、`features.multi_agent_v2.root_agent_usage_hint_text`（`spawn_agent` のツール説明に挿入されるテキスト）を通じて指示を出してください。

なお、`codex review`（TUI での `/review`）はサブエージェントとは別の仕組みであるため、サブエージェントを無効化していても利用可能です。
