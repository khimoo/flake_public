# Hermes Agent

Nous Research の Hermes Agent を `hermes` として入れる。
作業の経験から手順をスキルとして書き足し、使いながら直す AI エージェントである。
パッケージは [llm-agents.nix](https://github.com/numtide/llm-agents.nix) の `hermes-agent` を使い、[hermes_agent.star](../../../config/elements/hermes_agent.star) が入れる。[use_ai_agents.star](../../../config/elements/use_ai_agents.star) の `requires` にあるので、AI エージェントを使う利用目的（`programming` など）を選んだユーザーに入る。

## 初回の設定

対話式のウィザードでモデルとプロバイダを選ぶ。

```bash
hermes setup
```

「ChatGPT or Codex Subscription」を選ぶと、ChatGPT か Codex のサブスクリプションで使える。後から選び直すときは `hermes model` を使う。
設定、認証情報、記憶、スキルは `~/.hermes/` に保存される。Nix store や Git には入れない。

## 使う

```bash
hermes
```

込み入った作業を終えたときや訂正を受けたときに、Hermes が手順を SKILL.md 形式のスキルとして `~/.hermes/skills/` に書く。何を学んだかは、このディレクトリを読んで確かめる。
既定では承認なしで書き込む。書き込みを承認制にするには、対話中に `/skills approval on` を実行する（`~/.hermes/config.yaml` の `skills.write_approval` が `true` になる）。

## やめる

`~/.hermes/` を消すと、設定、記憶、スキルが消えて初回の状態に戻る。
コマンドを外すときは、[use_ai_agents.star](../../../config/elements/use_ai_agents.star) の `requires` から `hermes_agent` を除いて rebuild する。

## 版を上げる

リポジトリ内で、Claude Code・Codex と共通の input を更新する。

```bash
nix flake update llm-agents
```

[単体 build](../validation.md#対象別の確認手順) と `hermes --version` で確認し、[README の適用手順](../../../README.md) に従って rebuild する。

## 設計

### スキルと記憶を Nix で管理しない

試用の段階なので、Hermes の既定どおり `~/.hermes/` に書かせ、agents-private とは共有しない。
agents-private のスキルは live symlink で Claude Code と Codex から読まれているので、Hermes に書かせると、書いた時点で両者の挙動が変わる。
共有するかどうかは、Hermes が書くスキルの質を見てから決める。共有する場合は `skills.create_dir`（新しいスキルの書き込み先）と `skills.external_dirs`（読み込むだけの追加ディレクトリ）を使う。
上の設定項目とコマンドは v0.23.0 のソースで確かめた。

### 共通 input で版を固定する

取得元の選択とキャッシュの扱いは [AI エージェントの設計](../../architecture/unstable-packages.md#ai-エージェントは-llm-agentsnix-から取る) を参照。
