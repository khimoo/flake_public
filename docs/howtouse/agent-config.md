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
│   └── skills/            # 共有 skill の実体 (~/.claude/skills になる)
│       └── <skill-name>/SKILL.md
├── claude/
│   ├── CLAUDE.md          # ~/.claude/CLAUDE.md になる。先頭で `@../shared/AGENTS.md` を import する
│   ├── managed-settings.json # 方針。NixOS で /etc/claude-code/managed-settings.json になる（全ユーザーに掛かる）
│   ├── profiles/
│   │   └── <name>.json    # モデル別プロファイル。`claude-<name>` が `--settings` で重ねる
│   ├── hooks/             # hook スクリプト（任意）
│   ├── output-styles/     # output style（任意）
│   ├── agents/            # subagent 定義（任意）
│   └── commands/          # カスタム slash command（任意）
└── codex/
    ├── skills/            # ~/.agents/skills になる。専用 skill と ../../shared/skills/<name> へのリンク
    ├── <name>.config.toml # モデル別プロファイル。~/.codex/<name>.config.toml になり `codex-<name>` が `--profile` で重ねる
    └── rules/
        └── base.rules     # ~/.codex/rules/base.rules になる。人が書く実行ポリシー
```

任意のディレクトリは、まだ無ければ作らなくてよい（symlink は張られるが repo 側が
空なら「設定なし」に見えるだけ）。使いたくなった時点で repo にそのディレクトリを
作れば、**rebuild なしで即 live になる**。

`CLAUDE.md` の `@import` は symlink の置き場所ではなく実体のディレクトリを基準に
解決されるので、`~/.claude/CLAUDE.md` 経由でも `@../shared/AGENTS.md` は
`<root>/shared/AGENTS.md` を指す。

## モデル別プロファイル

モデルごとに変える値（model、reasoning effort）は指示文ではなくプロファイルに置き、
起動コマンドで選ぶ。名前は home モジュールで宣言する:

```nix
local.profile.agentProfiles = {
  claude = [ "opus" "fable" ];   # <root>/claude/profiles/opus.json, fable.json
  codex = [ "astra" ];           # <root>/codex/astra.config.toml
};
```

宣言した名前ごとに PATH 上の実行ファイル `claude-<name>`（`claude --settings <root>/claude/profiles/<name>.json "$@"`）と
`codex-<name>`（`codex --profile <name> "$@"`）ができる。素の `claude` `codex` はそのまま残り、
プロファイル無しの起動では `~/.claude/settings.json`（アプリが書く live ファイル）の `model` と Codex の live 設定が使われる。

- プロファイルの中身は起動時に読まれるので、編集に switch は要らない。**名前の追加・削除は switch が要る**
- `claude-<name> --resume` は transcript のモデルを優先する。再開時にモデルを変えるなら `--model` を足す
- セッション内の `/model` は `~/.claude/settings.json` に書き戻す。このファイルは repo で追跡しない。プロファイルで起動している間はコマンドライン層が勝つので、保存した値は次回のプロファイル無し起動で効く
- Codex の `--profile` は一回しか渡せず、`codex features` などの管理系サブコマンドには効かない。プロファイルは既定の `~/.codex` にだけ張るので `CODEX_HOME` を変えた起動には効かない。**存在しないプロファイル名を渡しても Codex は黙って無視する**（0.153.4 で exit 0、警告なし）ので、効いているかは TUI の表示モデルか `codex-<name> exec --json` の出力で確かめる
- happy は `codex app-server` を直接起動して `--profile` を渡さないので、この仕組みの対象外
- Claude のプロファイルは `settings.json` の上に重なる差分なので、`model` と `effortLevel` のように変えたい値だけを書く。hooks や plugins を写さない

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
- switch が要るのは、プロファイル名を足す・消すときと、Claude Code か Codex が**全く新しい
  カテゴリ**を導入してそれを使い始めるとき（`claude.nix` の `claudeDirs` か `codex.nix` の
  `home.file` に 1 行足す）
- 方針（フック、`enabledPlugins`、`extraKnownMarketplaces`、`outputStyle`、`language`）は
  `claude/managed-settings.json` に書く。NixOS では `local.claudeManagedSettings` で
  `/etc/claude-code/managed-settings.json` から直接リンクされ、マシンの全ユーザーに掛かる。
  repo を直せば次のセッションから効く。JSON が壊れていると Claude Code が起動しない
- `~/.claude/settings.json` は Claude Code が書く live ファイルで、repo で追跡しない。
  `/model` や `/config`、`/plugin` で試したプラグインはここに入る。常用すると決めたプラグインは
  `claude/managed-settings.json` に移す
- 全プロジェクト共通の指示は `shared/AGENTS.md` に書く。Claude Code だけに効かせたい指示は
  `claude/CLAUDE.md` の import の下に書く
- skills は Claude Code と Codex で同じ `SKILL.md` 形式。片方だけが解釈する frontmatter の
  キーは、もう片方には無視される
- マシン固有値は `managed-settings.json` と `base.rules` に入れない。マシン固有の指示は[下記](#マシン固有の指示)のホスト設定に書く。プロジェクト固有のローカル値は
  各プロジェクトの `.claude/settings.local.json` や `.codex/`、一時的な変更は起動引数を使う
- live な設定は Nix 世代のロールバックでは戻らない。設定 repo の Git 履歴で復元する

Claude の[設定スコープ](https://code.claude.com/docs/en/settings)と
Codex の[設定レイヤ](https://learn.chatgpt.com/docs/config-file/config-advanced)も参照。

## マシン固有の指示

設定 repo の指示は全マシン共通なので、特定のマシンだけで守らせたい指示は flake_public のホスト設定に書く。
例: spin713 の「メモリや GPU を多く使う処理はまずデスクトップで実行できるか確かめ、できなければフリーズしないか概算してから手元で実行する」（[hosts/nixos-spin713/agent-instructions.md](../../hosts/nixos-spin713/agent-instructions.md)）。

1. `hosts/<host>/agent-instructions.md` に指示を書く
2. そのホストの `default.nix` で読み込む:

   ```nix
   local.agentInstructions = builtins.readFile ./agent-instructions.md;
   ```

3. switch する

同じ本文が、Claude Code には `/etc/claude-code/CLAUDE.md`（管理者用の指示）として、Codex には `/etc/codex/config.toml` の `developer_instructions` として入る。
本文は Nix store を経由するので、編集したら switch が要る。設定 repo の指示と違い、即反映はされない。
対象は NixOS ホストだけで、standalone home-manager（WSL、macOS）には入らない。

switch 後の確認:

- Claude Code: セッションで `/context` を開き、**Memory files** に `/etc/claude-code/CLAUDE.md` があるか見る
- Codex: `grep developer_instructions /etc/codex/config.toml` で書き出されたことを確かめ、セッションで「このマシン固有の指示を要約して」と聞く

設計判断は [../architecture/agent-config.md](../architecture/agent-config.md#マシン固有の指示はシステム層に置く) を参照。

## Claude の方針（managed settings）

NixOS のホストで `local.claudeManagedSettings` に設定 repo の `claude/managed-settings.json` の
絶対パスを渡すと、`/etc/claude-code/managed-settings.json` がそのファイルへの直接リンクになる。

```nix
local.claudeManagedSettings = "/home/pomu/sagyo/agents-private/claude/managed-settings.json";
```

- 効いているかは、セッションの `/status` の **Setting sources** に managed settings が出るかで確かめる
- マシンの全ユーザーに掛かる。フックのコマンドは、フックのファイルが無いユーザーでは何もせずに終える形にする
- 以前 `~/.claude/settings.json` を設定 repo へリンクしていたマシンでは、最初の activation が
  リンクを普通のファイルに一度だけ移し替える（方針の項目は除く）。`agentConfigRoot` を無効化しても、
  `~/.claude/settings.json` は普通のファイルとして残る

設計判断は [../architecture/agent-config.md](../architecture/agent-config.md#claude-の方針は-managed-settings-に置きlive-設定は追跡しない) を参照。
