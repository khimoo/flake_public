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
│   ├── settings.json      # 方針。agent-sync が ~/.claude/settings.json の同じキーへ反映する
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
起動コマンドで選ぶ。名簿は設定 repo のファイルそのもので、flake_public には書かない:

- `<root>/claude/profiles/<name>.json` を置くと、起動コマンド `claude-<name>`（`claude --settings <root>/claude/profiles/<name>.json "$@"`）ができる
- `<root>/codex/<name>.config.toml` を置くと、`~/.codex/<name>.config.toml` へのリンクと起動コマンド `codex-<name>`（`codex --profile <name> "$@"`）ができる

作るのは `agent-sync`（[agent-sync.nix](../../modules/home-manager/dev/agent-sync.nix)）で、switch のたびと、
Linux では設定 repo の `claude/profiles/`・`claude/settings.json`・`codex/` が変わったとき（systemd の path unit）に走る。
手で走らせるときは `agent-sync`（`--dry-run` で予定だけを表示）。起動コマンドは
`~/.local/share/agent-launchers/bin` に置き、Home Manager のセッション変数で PATH に足す
（設定の適用後に開いたログインセッションから PATH に入る）。ファイルを消すと、対応する起動コマンドとリンクも消える。
名前に使えるのは英数字と `_` `-` だけで、それ以外の名前のファイルは警告して飛ばす。
素の `claude` `codex` はそのまま残り、プロファイル無しの起動では `~/.claude/settings.json`（アプリが書く live ファイル）の `model` と Codex の live 設定が使われる。

- プロファイルの中身は起動時に読まれるので、編集に switch は要らない。名前の追加・削除も switch は要らない（Linux）
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
2. 対象ユーザーの home モジュール（既存 2 台では `profiles/home/pomu-agents.nix`。`pomu-workstation.nix` がこれを import する）に clone 先を指定する:

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

rebuild で消えるのは、Home Manager が張ったリンク（`~/.claude/skills` など）と、`agent-sync` のコマンドと path unit だけ。
`agent-sync` が作ったファイルと `~/.claude/settings.json` に書き込んだキーは残る。起動コマンドは、次のログインから PATH に入らなくなる。
残したくなければ、rebuild の後に Claude Code と Codex を閉じてから次を消す（`<root>` は外した `agentConfigRoot`）。

1. 起動コマンド:

   ```sh
   rm -r ~/.local/share/agent-launchers
   ```

2. Codex のプロファイルへのリンク。一つめのコマンドで対象を確かめてから消す:

   ```sh
   find ~/.codex -maxdepth 1 -type l -name '*.config.toml' -lname '<root>/codex/*'
   find ~/.codex -maxdepth 1 -type l -name '*.config.toml' -lname '<root>/codex/*' -delete
   ```

3. `~/.claude/settings.json` に反映したキー。反映したキーの一覧は `~/.local/state/agent-sync/claude-managed-paths.json` にある:

   ```sh
   (umask 077; jq --slurpfile p ~/.local/state/agent-sync/claude-managed-paths.json 'delpaths($p[0])' \
     ~/.claude/settings.json > ~/.claude/settings.json.new)
   mv ~/.claude/settings.json.new ~/.claude/settings.json
   rm -r ~/.local/state/agent-sync
   ```

## 日常運用

- skill / agent / command / output-style / 指示の追加・編集は設定 repo 側で直接行う。
  out-of-store symlink なので **rebuild 不要で即反映**される
- 各カテゴリディレクトリ全体が repo への symlink のため、中身は必ず repo 側で作る
  （`~/.claude/skills/` 直下に手でディレクトリを作ると repo に入る）
- switch が要るのは、Claude Code か Codex が**全く新しいカテゴリ**を導入してそれを使い始めるとき
  （`claude.nix` の `claudeDirs` か `codex.nix` の `home.file` に 1 行足す）
- 方針（フック、`enabledPlugins`、`extraKnownMarketplaces`、`outputStyle`、`language`、`env`）は
  `claude/settings.json` に書く。`agent-sync` が `~/.claude/settings.json` の同じキーへ反映する（[下記](#claude-の方針)）
- `~/.claude/settings.json` は Claude Code が書く live ファイルで、repo で追跡しない。
  `/model` や `/config`、`/plugin` で試したプラグインはここに入る。常用すると決めたプラグインは
  `claude/settings.json` に移す
- プラグインのフックとコマンドは Claude Code の PATH で実行される。Node.js はシェルに入れていないので、
  Claude Code のラッパーが PATH の末尾に足している（[claude-code-node.nix](../../overlays/claude-code-node.nix)）
- 全プロジェクト共通の指示は `shared/AGENTS.md` に書く。Claude Code だけに効かせたい指示は
  `claude/CLAUDE.md` の import の下に書く
- skills は Claude Code と Codex で同じ `SKILL.md` 形式。片方だけが解釈する frontmatter の
  キーは、もう片方には無視される
- マシン固有値は `claude/settings.json` と `base.rules` に入れない。マシン固有の指示は[下記](#マシン固有の指示)のホスト設定に書く。プロジェクト固有のローカル値は
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
対象は NixOS ホスト（nixos-work-wsl を含む）だけで、standalone home-manager（macOS）には入らない。

switch 後の確認:

- Claude Code: セッションで `/context` を開き、**Memory files** に `/etc/claude-code/CLAUDE.md` があるか見る
- Codex: `grep developer_instructions /etc/codex/config.toml` で書き出されたことを確かめ、セッションで「このマシン固有の指示を要約して」と聞く

設計判断は [../architecture/agent-config.md](../architecture/agent-config.md#マシン固有の指示はシステム層に置く) を参照。

## Claude の方針

設定 repo の `claude/settings.json` のキーを、`agent-sync` が `~/.claude/settings.json` へ反映する。
`agentConfigRoot` を設定したユーザーだけに掛かる。

- 設定 repo にあるキーは設定 repo の値になる。値がオブジェクトのキー（`enabledPlugins`、`env`、`hooks` など）は
  一段下のキーごとに反映するので、`/plugin` で試しているプラグインのように設定 repo にないキーは残る
- 設定 repo から消したキーは、`~/.claude/settings.json` からも消える。それ以外のキー（`model`、`theme` など）は触らない
- 設定 repo にあるキーをアプリの中で変えると、次の反映で設定 repo の値に戻る。前回の反映の後に変わっていたキーは警告する
- どちらかの JSON が壊れていると反映を止め、`~/.claude/settings.json` を変えない（switch は止めない）
- Linux では設定 repo の `claude/settings.json` を保存すると反映される。反映は次のセッションから効く

設計判断は [../architecture/agent-config.md](../architecture/agent-config.md#claude-の方針は設定-repo-からユーザー設定へ反映する) を参照。
