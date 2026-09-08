# Codex のサブエージェント無効化（設計判断）

使い方は [docs/howtouse/codex-subagents.md](../howtouse/codex-subagents.md) を参照。
実装: [modules/nixos/codex.nix](../../modules/nixos/codex.nix)

## 何を解決するか

Codex CLI のサブエージェント（MultiAgentV2）は既定で親の会話履歴を全部コピーして
子エージェントに渡す。`spawn_agent` の `fork_turns` 引数を省略すると `"all"`
（`SpawnAgentForkMode::FullHistory`）になるため、子を N 個生やすと入力トークンが
親のコンテキスト長 × N に膨らむ。

旧世代（v1）の `spawn_agent` は `fork_context`（真偽値、既定 `false`）で、明示的に
指定しない限り子は白紙から始まった。v2 で既定が反転している。Claude Code の
subagent と同じ感覚で使うと想定外のトークンを消費する。

さらに全履歴 fork では `agent_type` / `model` / `reasoning_effort` の指定が拒否される
（"Full-history forked agents inherit the parent agent type, model, and reasoning
effort"）ため、安いモデルへ委譲することもできない。

導入判断時点（2026-09-07）で `~/.codex/sessions` の全セッションと
`state_5.sqlite` の `thread_spawn_edges` を走査したところ、`spawn_agent` の呼び出しは
0 件だった。使っていない機能に既定でトークンを払っている状態だったので無効化した。

コードレビューは `codex review`（TUI では `/review`）が `TaskKind::Review` として
履歴を持たない別スレッドで走る独立機能なので、無効化しても失われない
（`codex-rs/core/src/tasks/review.rs` が `initial_history: None` で
`run_codex_thread_one_shot` を呼ぶ）。

## 採った方式: `/etc/codex/config.toml`（システム層）

Codex の設定はレイヤ構造になっており、下から順に上書きされる
（`codex-rs/config/src/loader/mod.rs` のドキュメントコメント）:

| 層 | パス | 誰が書くか |
|----|------|-----------|
| system | `/etc/codex/config.toml` | 管理者（= この flake） |
| user | `~/.codex/config.toml` | Codex 自身と手動編集 |
| project | `<repo>/.codex/config.toml` | リポジトリ（信頼済みのみ） |
| runtime | `-c key=value` フラグ | 起動ごと |

system 層を NixOS の `environment.etc` で宣言する。nix store の読み取り専用ファイルに
なるため Codex が書き換えることはなく、判断の根拠と戻し方をコメントとして安全に置ける。

`agents.enabled = false` と `features.multi_agent_v2 = false` の両方を書く必要がある。
`multi_agent_version_override`（`codex-rs/core/src/config/mod.rs`）は
`features.multi_agent_v2` が有効なら無条件で v2 を選ぶため、`agents.enabled` だけでは
モデル側のピン留めで v2 が復活する経路が残る。

## 検討して退けた案

### `~/.codex/config.toml` を設定 repo への out-of-store symlink にする

[claude-config.md](./claude-config.md) と同じ方式。Codex は書き込み前に symlink 鎖を
辿って実体に書く（`codex-rs/utils/path-utils/src/lib.rs` の
`resolve_symlink_write_paths`）ので技術的には成立し、WSL や macOS でも効く。

退けた理由は、`~/.codex/config.toml` が設定ではなく**アプリケーション状態**の置き場
だから。Codex は信頼済みディレクトリ（`[projects."<絶対パス>"]`）、TUI で選んだモデル、
NUX カウンタをここに書き込む。git 管理下に置くとこれらが差分として出続け、しかも
絶対パスは Linux と macOS で食い違う。Claude Code に層の仕組みがないから symlink 方式を
取っているのであって、層がある Codex で同じことをする理由はない。

### home-manager の `programs.codex`

`settings` から config.toml を生成して store の読み取り専用ファイルとして配置する。
Codex 側の書き込みが失敗するうえ、生成物なのでコメントを書けない。

### リポジトリごとの `.codex/config.toml`

プロジェクト層は信頼済みディレクトリでのみ有効で、リポジトリ単位にしか効かない。
グローバルな挙動の設定には合わない。

### プロファイル層（`~/.codex/<name>.config.toml`）

ローダのドキュメントには存在するが、0.153.4 では `-c profile=<name>` を渡しても
層として読まれなかった。使えない。

## 戻す条件

- OpenAI 側が `fork_turns` の既定を `"none"` 相当に変えた
- 並列調査をサブエージェントに任せたくなった

全部戻さずトークンだけ抑えるなら、`features.multi_agent_v2` を有効にしたうえで
`root_agent_usage_hint_text`（`spawn_agent` のツール説明文に差し込まれる）へ
`fork_turns="none"` で呼ぶよう書く方法もある。
