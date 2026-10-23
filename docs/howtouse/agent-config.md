# エージェント設定（Claude Code / Codex）

Claude Code と Codex のユーザー設定（共通の指示、スキル、Claude の settings と output style、Codex の実行ポリシーなど）は、専用の設定リポジトリ（agents-private）で一元管理し、`~/.claude/`、`~/.codex/`、`~/.agents/` からそのローカルリポジトリへシンボリックリンクを貼る構成にしています。
これにより、設定リポジトリ内のファイルを編集するだけで、switch を行わなくても即座に変更が反映されます。

設計: [エージェント設定の設計](../architecture/agent-config.md)

## 設定をどこに書くか

設定リポジトリ内のディレクトリ構成は以下のとおりです。

```
<agentConfigRoot>/
├── shared/
│   ├── AGENTS.md          # 全プロジェクト共通の指示。Codex は ~/.codex/AGENTS.md として参照し、Claude は claude/CLAUDE.md 内の @import で読み込む
│   └── skills/<name>/     # 共通スキル（~/.claude/skills に反映）
├── claude/
│   ├── CLAUDE.md          # ~/.claude/CLAUDE.md。冒頭で @../shared/AGENTS.md を import
│   ├── settings.json      # 全体方針。agent-sync が ~/.claude/settings.json へ同期する
│   ├── profiles/<name>.json  # claude-<name> で上書き適用するプロファイル
│   └── hooks/ output-styles/ agents/ commands/
└── codex/
    ├── skills/            # ~/.agents/skills に反映。Codex 専用スキルおよび ../../shared/skills/<name> へのリンク
    ├── <name>.config.toml # codex-<name> で上書き適用するプロファイル
    ├── launch.py          # codex-<name> から呼び出される起動スクリプト
    └── rules/base.rules   # ~/.codex/rules/base.rules。手動で記述する実行ポリシー
```

- 両方のエージェントに共通で適用したい指示は `shared/AGENTS.md` に、Claude Code 固有の指示は `claude/CLAUDE.md` の import 文より下に記述します。
- 共通スキルを Codex でも利用したい場合は、`codex/skills/<name>` から `../../shared/skills/<name>` へのリンクを作成します。
- スキル、エージェント、コマンド、output style は、`~/.claude/` 配下ではなく設定リポジトリ側に作成してください。カテゴリごとのディレクトリがシンボリックリンクになっているため、`~/.claude/skills/` 配下に作成したファイルもリポジトリ側に入ります。
- フックや `enabledPlugins`、`extraKnownMarketplaces`、`outputStyle`、`language`、`env` などの設定は `claude/settings.json` に記述します（[Claude の方針](#claude-の方針) 参照）。
- マシンごとに異なる指示は設定リポジトリではなく、[ホスト設定](#マシン固有の指示) に記述してください。特定プロジェクト固有の設定値は、そのプロジェクト内の `.claude/settings.local.json` や `.codex/` に記載します。

以下のファイルは各ツールが動的に書き込むため、設定リポジトリの Git 管理対象外としています。

- `~/.claude/settings.json`: `/model`、`/config`、`/plugin` などの実行結果が書き込まれます。常用するプラグインは `claude/settings.json` に手動で移してください。
- `~/.codex/config.toml`: 信頼済みディレクトリや選択されたモデルが記録されます。全マシン共通の設定は `/etc/codex/config.toml`（[codex-subagents.md](./codex-subagents.md) 参照）に、モデルごとの設定はプロファイルに記述します。
- `~/.codex/rules/default.rules`: 承認プロンプトで「always allow」を選択した際に追記されます。永続的なルールとして残したい行は `base.rules` に移動してください。なお、`base.rules` で定義された `forbidden` や `prompt` が、`default.rules` の `allow` によって緩和されることはありません。

Claude Code や Codex が新しい種別の設定ディレクトリを読み込むようになった場合のみ、`claude.nix` の `claudeDirs` や `codex.nix` の `home.file` に追加して switch を実行します。
これらの設定は Nix の世代を戻してもロールバックされないため、設定リポジトリ側の Git 履歴を用いて復元してください。

## モデルの系列を選んで起動する

設定リポジトリに `claude/profiles/<name>.json` を置くと `claude-<name>` が、`codex/<name>.config.toml` を置くと `codex-<name>` コマンドが利用可能になります。
プロファイルや設定ファイルには、特定のバージョンが付与されたモデル ID は記述しません。これにより、その系列に新しいバージョンがリリースされた場合でも、設定を書き換えることなく自動で最新版が使用されます。

- Claude のプロファイルは `~/.claude/settings.json` に対する差分として適用されるため、`model`（`opus`、`fable` などのエイリアス）や `effortLevel` といった変更したい項目のみを記述します。
- `codex-<name>` は起動時に `codex debug models` を確認し、ID が `gpt-<版>-<name>` となるモデルの中から最も新しいバージョンを自動で選択します。一致するモデルが見つからない場合は起動しません。子エージェントのモデルを指定せずに起動（spawn）した場合は、sol の最新版が利用されます。
- デフォルトの `claude` および `codex` コマンドもそのまま利用でき、これらはプロファイルなしの設定で起動します。

起動用コマンドは `agent-sync` によって `~/.local/share/agent-launchers/bin` 配下に自動生成されます。
この同期は switch の実行時や、Linux 環境では設定リポジトリの `claude/profiles/`、`claude/settings.json`、`codex/` に変更があったタイミングで自動実行されます。手動で実行したい場合は `agent-sync`（`--dry-run` を指定すると実行予定の確認のみ）を実行してください。
コマンドへの PATH は、設定を適用した後に新しく開いたログインセッションから有効になります。
プロファイルファイルを削除すると、対応する起動コマンドやシンボリックリンクも削除されます。なお、ファイル名に使用できるのは英数字と `_`、`-` のみであり、それ以外の名前のファイルは警告を出してスキップされます。

注意点:

- `claude-<name> --resume` は過去の会話履歴（transcript）に記録されたモデルを使用します。セッション再開時にモデルを変更したい場合は `--model` を指定してください。
- Codex は存在しないプロファイル名が指定されても警告を出さずに無視します（バージョン 0.153.4 時点）。プロファイルが適用されているかは、TUI 上に表示されるモデル名や `codex-<name> exec --json` の出力結果で確認してください。
- Codex の `--profile` オプションは `codex features` などの管理系サブコマンドには適用されず、`CODEX_HOME` を変更して起動した場合にも反映されません。また、happy は `codex app-server` を直接起動するためプロファイルの対象外となります。
- TUI 上でモデルをデフォルトとして保存すると、`~/.codex/config.toml` にバージョン固定の `model` が書き込まれます。

## マシンに入れる・外す

1. 設定リポジトリを clone します（[private-repo-clone.md](./private-repo-clone.md) を使って自動化することも可能です）。
2. 対象ユーザーの home モジュールで clone 先のパスを指定し、switch を実行します。pomu では [pomu-agents.nix](../../profiles/home/pomu-agents.nix) に記述されています。

   ```nix
   local.profile.agentConfigRoot = "/home/pomu/sagyo/agents-private";
   ```

すでに存在する `~/.claude/skills` などのディレクトリは、Home Manager によって `.bak` 拡張子付きで自動退避されます。

設定を解除（アンインストール）する際は、`agentConfigRoot` と（自動 clone を利用している場合は）`agentConfigRepo` の両方を削除してから switch してください（URL だけを残すと評価時にエラーになります）。
switch 実行によって削除されるのは Home Manager が管理するリンクと `agent-sync` の path unit のみで、生成済みの起動コマンド、Codex プロファイルへのリンク、および `~/.claude/settings.json` に反映されたキーは残ります。
これらも完全に削除したい場合は、Claude Code と Codex を終了させたうえで以下のクリーンアップ処理を実行してください（`<root>` は解除した `agentConfigRoot` のパスに置き換えてください）。

```sh
rm -r ~/.local/share/agent-launchers
find ~/.codex -maxdepth 1 -type l -name '*.config.toml' -lname '<root>/codex/*'          # 削除対象を確認
find ~/.codex -maxdepth 1 -type l -name '*.config.toml' -lname '<root>/codex/*' -delete
(umask 077; jq --slurpfile p ~/.local/state/agent-sync/claude-managed-paths.json 'delpaths($p[0])' \
  ~/.claude/settings.json > ~/.claude/settings.json.new)
mv ~/.claude/settings.json.new ~/.claude/settings.json
rm -r ~/.local/state/agent-sync
```

## マシン固有の指示

特定のマシンでのみ守らせたい指示がある場合は、flake_public のホスト設定に記述します。
設定例としては spin713 の [agent-instructions.md](../../hosts/nixos-spin713/agent-instructions.md) を参照してください。

1. `hosts/<host>/agent-instructions.md` に指示内容を記述します。
2. 該当ホストの `default.nix` で `local.agentInstructions = builtins.readFile ./agent-instructions.md;` として読み込みます。
3. switch を実行します。テキスト内容は Nix store を経由して配置されるため、ファイルを編集するたびに switch が必要です。

Claude Code では `/etc/claude-code/CLAUDE.md` として、Codex では `/etc/codex/config.toml` の `developer_instructions` 項目として反映されます。
この機能は NixOS ホスト（nixos-work-wsl を含む）のみが対象であり、macOS のスタンドアロン Home Manager 環境には適用されません。

switch 後の反映確認方法:

- Claude Code: `/context` コマンドを実行し、**Memory files** に `/etc/claude-code/CLAUDE.md` が含まれているか確認します。
- Codex: `grep developer_instructions /etc/codex/config.toml` で内容が書き出されているか確認し、対話セッションで「このマシン固有の指示を要約して」と質問して応答を確認します。

## Claude の方針

設定リポジトリの `claude/settings.json` に定義された各キーは、`agent-sync` によって `~/.claude/settings.json` へ反映されます。Linux 環境ではファイルを保存すると自動で同期され、次回のセッションから適用されます。

- 設定リポジトリで定義されているキーの値は、設定リポジトリの内容で上書きされます。アプリ内から一時的に変更しても次の同期処理で元の値に戻され、前回の同期から変更されていた場合は警告が表示されます。
- オブジェクト型の値を持つキー（`enabledPlugins`、`env`、`hooks` など）は、配下のプロパティ単位でマージ同期されます。そのため、`/plugin` コマンドなどで一時的に追加した設定リポジトリ側にないキーはそのまま残ります。
- 設定リポジトリから削除されたキーは、`~/.claude/settings.json` 側からも削除されます。なお、設定リポジトリ側で未定義のキー（`model` や `theme` など）には影響を与えません。
- いずれかの JSON ファイルが構文エラーなどで破損している場合は同期処理を安全に中断し、`~/.claude/settings.json` を変更しません（switch 自体は失敗させずに継続します）。
