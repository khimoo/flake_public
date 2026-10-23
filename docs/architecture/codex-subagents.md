# Codex のサブエージェントの設計

使い方: [Codex のサブエージェント](../howtouse/codex-subagents.md)
実装: [modules/nixos/codex.nix](../../modules/nixos/codex.nix)

## 既定ではサブエージェントを無効にする

Codex CLI のサブエージェント（MultiAgentV2）は、`spawn_agent` の `fork_turns` を省くと `"all"`（`SpawnAgentForkMode::FullHistory`）になり、親の会話履歴を全部子に渡す。子を N 個作ると、入力のトークンが親の長さの N 倍になる。
旧世代（v1）の `fork_context` は既定が `false` で、子は何も持たずに始まった。v2 で既定が逆になったので、Claude Code の subagent と同じつもりで使うと想定外にトークンを使う。
全履歴の fork では `agent_type`、`model`、`reasoning_effort` の指定も拒否される（"Full-history forked agents inherit the parent agent type, model, and reasoning effort"）ので、安いモデルに任せることもできない。

決めたとき（2026-09-07）の `~/.codex/sessions` と `state_5.sqlite` の `thread_spawn_edges` には、`spawn_agent` の呼び出しが 0 件だった。使っていない機能で、将来うっかり全履歴を fork しないように無効にした保守的な判断である。
`codex review` は `TaskKind::Review` として履歴を持たない別のスレッドで動く（`codex-rs/core/src/tasks/review.rs` が `initial_history: None` で `run_codex_thread_one_shot` を呼ぶ）ので、無効にしても使える。

`codex-astra` だけは、agents-private の `codex/astra.config.toml` で `multi_agent_v2 = true` にしている。sol-handoff で `sol-worker` を spawn し、終わった子に追加の指示を送るためで、子のモデルは `agents.default_subagent_model` で sol にしている（[agent-config.md](./agent-config.md)）。

## system 層の `/etc/codex/config.toml` に書く

Codex の設定は、system（`/etc/codex/config.toml`）、user（`~/.codex/config.toml`）、profile（`--profile <name>` のときの `~/.codex/<name>.config.toml`）、project（信頼したリポジトリの `.codex/config.toml`）、runtime（`-c key=value`）の順に重なり、後のものが上書きする（`codex-rs/config/src/loader/mod.rs` のドキュメントコメント）。
system 層を NixOS の `environment.etc` で宣言すると、nix store の読み取り専用のファイルになり、Codex に書き換えられない。

`agents.enabled = false` と `features.multi_agent_v2 = false` の両方を書く。`multi_agent_version_override`（`codex-rs/core/src/config/mod.rs`）は、`features.multi_agent_v2` が有効なら無条件に v2 を選ぶので、`agents.enabled` だけではモデルの側の指定で v2 が戻る。
`~/.codex/config.toml` に同じキーを書くと、system 層の値は使われなくなる。

退けた案と理由:

- `~/.codex/config.toml` を設定 repo への symlink にする: Codex は symlink をたどって実体に書く（`codex-rs/utils/path-utils/src/lib.rs` の `resolve_symlink_write_paths`）ので成り立つが、このファイルは信頼済みディレクトリ（`[projects."<絶対パス>"]`）、TUI で選んだモデル、NUX のカウンタが書き込まれるアプリの状態の置き場で、git で追うと差分が出続け、絶対パスは Linux と macOS で食い違う
- home-manager の `programs.codex`: store の読み取り専用のファイルになり、Codex の書き込みが失敗する。生成物なのでコメントも書けない
- リポジトリごとの `.codex/config.toml`: 信頼したリポジトリの中でしか効かない
- profile 層: `--profile` は一回しか渡せず、起動ごとに指定が要る。常に効かせたい設定には向かない（0.153.4 で、`-c profile=<name>` では読まれず `--profile` なら読まれることを確かめた）

## 戻す条件

- OpenAI が `fork_turns` の既定を `"none"` に相当するものに変えた
- 並列の調査をサブエージェントに任せたくなった

全部は戻さずにトークンだけ抑えるなら、`features.multi_agent_v2` を有効にし、`root_agent_usage_hint_text` に `fork_turns="none"` で呼ぶよう書く。
