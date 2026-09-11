# エージェント設定（Claude Code / Codex）の git 管理

`~/.claude/` と `~/.codex/` `~/.agents/` のうち git 管理したい設定（共通指示、skills、
Claude の settings と output style、Codex の実行ポリシー）を、別リポジトリの clone へ
symlink して管理する。

設計判断は [docs/architecture/agent-config.md](../architecture/agent-config.md) を参照。
実装: [modules/home-manager/dev/claude.nix](../../modules/home-manager/dev/claude.nix)、
[modules/home-manager/dev/codex.nix](../../modules/home-manager/dev/codex.nix)

## 設定 repo に期待するレイアウト

```
<agentConfigRoot>/
├── shared/
│   ├── AGENTS.md          # 全プロジェクト共通の指示 (~/.codex/AGENTS.md になる。Claude は claude/CLAUDE.md の @import で読む)
│   └── skills/            # skill 群 (~/.claude/skills と ~/.agents/skills の両方になる)
│       └── <skill-name>/SKILL.md
├── claude/
│   ├── CLAUDE.md          # ~/.claude/CLAUDE.md になる。先頭で `@../shared/AGENTS.md` を import する
│   ├── settings.json      # ~/.claude/settings.json になる（マシン固有値を入れない）
│   ├── hooks/             # hook スクリプト（任意）
│   ├── output-styles/     # output style（任意）
│   ├── agents/            # subagent 定義（任意）
│   └── commands/          # カスタム slash command（任意）
└── codex/
    └── rules/
        └── base.rules     # ~/.codex/rules/base.rules になる。人が書く実行ポリシー
```

任意のディレクトリは、まだ無ければ作らなくてよい（symlink は張られるが repo 側が
空なら「設定なし」に見えるだけ）。使いたくなった時点で repo にそのディレクトリを
作れば、**rebuild なしで即 live になる**。

`CLAUDE.md` の `@import` は symlink の置き場所ではなく実体のディレクトリを基準に
解決されるので、`~/.claude/CLAUDE.md` 経由でも `@../shared/AGENTS.md` は
`<root>/shared/AGENTS.md` を指す。

## 配線されないもの

- `~/.codex/config.toml`: Codex が信頼済みディレクトリ、選択中モデル、TUI のカウンタを
  書き込む live なファイル。全マシン共通で宣言したい設定は
  [codex-subagents.md](./codex-subagents.md) の `/etc/codex/config.toml`（system 層）、
  モデルごとに変える値は `~/.codex/<name>.config.toml`（`codex --profile <name>`）に置く
- `~/.codex/rules/default.rules`: 承認プロンプトの「always allow」が追記する live なファイル。
  `rules/` 配下の `*.rules` は全部読まれ、複数一致は最も厳しい決定が勝つので、
  `base.rules` に書いた `forbidden` / `prompt` を `default.rules` の `allow` が緩めることはない。
  `default.rules` に溜まった行のうち方針として残したいものは `base.rules` に移す
- 履歴、認証情報、キャッシュ

## マシンに挿す手順

1. 設定 repo を任意の場所に clone する
   （NixOS なら [private-repo-clone.md](./private-repo-clone.md) で自動 clone にできる）
2. 対象ユーザーの home モジュール（既存 2 台では `profiles/home/pomu-workstation.nix`）に clone 先を指定する:

   ```nix
   local.profile.agentConfigRoot = "/home/pomu/sagyo/agents-private";
   ```

3. rebuild する

既存の `~/.claude/skills` 等のディレクトリがあった場合は home-manager が `.bak` に退避する。
`~/.codex/rules/` は通常ディレクトリのまま残り、`base.rules` だけが symlink になる。

## 抜く手順

`local.profile.agentConfigRoot` と、自動 clone している場合は `local.profile.agentConfigRepo` の
指定を両方外して rebuild する（既定 null）。URL だけ残す設定は評価時に拒否される。
設定 repo を持たない環境・他人の利用では何も起きない。

## 日常運用

- skill / agent / command / output-style / 指示の追加・編集は設定 repo 側で直接行う。
  out-of-store symlink なので **rebuild 不要で即反映**される
- 各カテゴリディレクトリ全体が repo への symlink のため、中身は必ず repo 側で作る
  （`~/.claude/skills/` 直下に手でディレクトリを作ると repo に入る）
- switch が要るのは Claude Code か Codex が**全く新しいカテゴリ**を導入し、それを
  使い始めるときだけ（`claude.nix` の `claudeDirs` か `codex.nix` の `home.file` に 1 行足す）
- `claude/settings.json` は管理対象。`~/.claude/settings.json` は checkout への symlink で、
  `/model` や `/config` によるアプリからの編集も repo の差分になる。commit 前に残す行を選別する
- 全プロジェクト共通の指示は `shared/AGENTS.md` に書く。Claude Code だけに効かせたい指示は
  `claude/CLAUDE.md` の import の下に書く
- skills は Claude Code と Codex で同じ `SKILL.md` 形式。片方だけが解釈する frontmatter の
  キーは、もう片方には無視される
- マシン固有値は `settings.json` と `base.rules` に入れない。プロジェクト固有のローカル値は
  各プロジェクトの `.claude/settings.local.json` や `.codex/`、一時的な変更は起動引数を使う
- live な設定は Nix 世代のロールバックでは戻らない。設定 repo の Git 履歴で復元する

Claude の[設定スコープ](https://code.claude.com/docs/en/settings)と
Codex の[設定レイヤ](https://learn.chatgpt.com/docs/config-file/config-advanced)も参照。
