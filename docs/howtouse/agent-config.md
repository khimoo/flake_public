# エージェント設定（Claude Code / Codex）

Claude Code と Codex のユーザー設定（共通の指示、スキル、Claude の settings / output style、Codex の実行ポリシーなど）は、専用の設定リポジトリ（`agents-private`）で一元管理しています。
`~/.claude/`、`~/.codex/`、`~/.agents/` からローカルの設定リポジトリへシンボリックリンクを貼る構成にしているため、リポジトリ内のファイルを編集するだけで switch を実行することなく即座に変更が反映されます。

設計: [エージェント設定の設計](../architecture/agent-config.md)

## 設定ファイルの配置場所

設定リポジトリ内のディレクトリ構成は以下のとおりです。

```
<agentConfigRoot>/
├── shared/
│   ├── AGENTS.md             # 全プロジェクト共通の指示。Codex は ~/.codex/AGENTS.md として参照し、Claude は claude/CLAUDE.md 内の @import で読み込む
│   └── skills/<name>/        # 共通スキル（~/.claude/skills に反映）
├── claude/
│   ├── CLAUDE.md             # ~/.claude/CLAUDE.md。冒頭で @../shared/AGENTS.md をインポート
│   ├── settings.json         # 全体方針。agent-sync が ~/.claude/settings.json へ同期
│   ├── profiles/<name>.json  # claude-<name> で上書き適用するプロファイル
│   └── hooks/ output-styles/ agents/ commands/
└── codex/
    ├── skills/               # ~/.agents/skills に反映。Codex 専用スキルおよび ../../shared/skills/<name> へのリンク
    ├── <name>.config.toml    # codex-<name> で上書き適用するプロファイル
    ├── launch.py             # codex-<name> から呼び出される起動スクリプト
    └── rules/base.rules      # ~/.codex/rules/base.rules。手動で記述する実行ポリシー
```

- **共通指示と個別指示**: 両エージェント共通の指示は `shared/AGENTS.md` に、Claude Code 固有の指示は `claude/CLAUDE.md` の import 文より下に記述します。
- **スキルの共有**: 共通スキルを Codex でも利用する場合は、`codex/skills/<name>` から `../../shared/skills/<name>` への相対シンボリックリンクを作成します。
- **各種リソースの作成場所**: スキル、エージェント、カスタムコマンド、output style は `~/.claude/` 配下ではなく設定リポジトリ側に作成してください。カテゴリ別ディレクトリがシンボリックリンク化されているため、`~/.claude/skills/` 配下に直接作成したファイルもリポジトリ側に保存されます。
- **各種機能設定**: フックや `enabledPlugins`、`extraKnownMarketplaces`、`outputStyle`、`language`、`env` などの設定は `claude/settings.json` に記述します（詳細は [Claude の同期方針](#claude-の同期方針) を参照）。
- **マシン固有・プロジェクト固有設定**: マシン固有の指示は設定リポジトリではなく [ホスト設定](#マシン固有の指示) に記述します。特定プロジェクト固有の設定値は、対象プロジェクト内の `.claude/settings.local.json` や `.codex/` に配置してください。

以下のファイルは各ツールによって動的に書き込まれるため、設定リポジトリの Git 管理対象外としています。

- `~/.claude/settings.json`: `/model`、`/config`、`/plugin` などの実行結果が書き込まれます。恒常的に利用するプラグイン設定は `claude/settings.json` に手動で転記してください。
- `~/.codex/config.toml`: 信頼済みディレクトリや選択されたモデルが記録されます。全マシン共通の設定は `/etc/codex/config.toml`（[codex-subagents.md](./codex-subagents.md) 参照）に、モデルごとの設定はプロファイルに記述します。
- `~/.codex/rules/default.rules`: 承認プロンプトで「always allow」を選択した際に追記されます。永続的なルールとして維持したい行は `base.rules` に移動してください。なお、`base.rules` で定義された `forbidden` や `prompt` が、`default.rules` の `allow` によって緩和されることはありません。

Claude Code や Codex が新しい種別の設定ディレクトリを読み込むようになった場合は、[agent_links.star](../../config/elements/agent_links.star) のリンク一覧に対象を追加して switch を実行してください。
なお、これらの設定は Nix の世代をロールバックしても以前の状態には戻らないため、設定リポジトリの Git 履歴を用いて復元します。

## モデル系列を指定して起動する

設定リポジトリ内に `claude/profiles/<name>.json` を配置すると `claude-<name>` コマンドが、`codex/<name>.config.toml` を配置すると `codex-<name>` コマンドがそれぞれ利用可能になります。
プロファイルや設定ファイルには特定のバージョン番号を含まないモデル ID を指定します。これにより、該当系列の新しいバージョンがリリースされた場合でも、設定変更なしで自動的に最新版が適用されます。

- **Claude プロファイル**: `~/.claude/settings.json` に対する差分として適用されます。そのため、`model`（`opus`、`fable` などのエイリアス）や `effortLevel` など、変更対象の項目のみを記述します。
- **Codex プロファイル**: 起動時に `codex debug models` を参照し、ID が `gpt-<版>-<name>` に一致するモデルの中から最新バージョンを自動選択します。一致するモデルが存在しない場合は起動しません。なお、子エージェントのモデルを指定せずに起動（spawn）した場合は、最新版の `sol` が使用されます。
- **デフォルトコマンド**: 標準コマンド（`claude` および `codex`）も引き続き利用可能で、プロファイル非適用の状態で起動します。

起動用コマンドは `agent-sync` により `~/.local/share/agent-launchers/bin` 配下へ自動生成されます。
同期処理は switch 実行時や、Linux 環境において設定リポジトリの `claude/profiles/`、`claude/settings.json`、`codex/` 内のファイルが更新されたタイミングで自動実行されます。手動で実行したい場合は `agent-sync`（`--dry-run` を指定すると事前確認が可能）を実行してください。
生成されたコマンドへの PATH は、設定適用後に新しく開いたログインセッションから有効になります。
プロファイルファイルを削除すると、対応する起動コマンドやシンボリックリンクも連動して削除されます。なお、ファイル名に使用できる文字は英数字、`_`、`-` のみです。それ以外の文字を含むファイルは、警告を出力してスキップされます。

注意点:

- `claude-<name> --resume` は過去の会話履歴（transcript）に記録されたモデルを再利用します。セッション再開時にモデルを変更したい場合は、明示的に `--model` を指定してください。
- Codex は存在しないプロファイル名が指定されても警告を出さずに無視します（バージョン 0.153.4 時点）。プロファイルの適用状態は、TUI 上に表示されるモデル名や `codex-<name> exec --json` の出力結果で確認してください。
- Codex の `--profile` オプションは `codex features` などの管理系サブコマンドには適用されず、`CODEX_HOME` を変更して起動した場合にも反映されません。また、happy は `codex app-server` を直接起動するためプロファイルの適用対象外です。
- TUI 上でモデルをデフォルトとして保存すると、`~/.codex/config.toml` にバージョンが固定された `model` が書き込まれます。

## マシンへの導入とアンインストール

### 導入手順

1. 設定リポジトリを clone します（[private-repo-clone.md](./private-repo-clone.md) による自動化も可能です）。
2. [owner.toml](../../config/owner.toml) の `agent_config_root` にホームディレクトリからの相対パスを指定します。自動 clone を利用する場合は `agent_config_repo` にリポジトリ URL も指定してください。

   ```toml
   agent_config_root = "sagyo/agents-private"
   agent_config_repo = "git@example.org:user/agents-private.git"
   ```

3. 対象ホストの設定（`config/hosts/<ホスト>.toml`）において、該当ユーザーの `[[users]]` 内の `purposes` に AI エージェントを利用する purpose（`requires` に `use_ai_agents` を含む `programming` など）が含まれていることを確認し、switch を実行します。`use_ai_agents` により `agent_config` と `agent_compression` が取り込まれます（同一定義を AI エージェントを利用する各ホストで共有します）。

圧縮プラグインの既定モードは、同一ユーザーファイル内で `agent_compression = {"caveman": "off", "genshijin": "normal"}` のように指定します。キーを省略するか値を `None` に設定した場合は、該当プラグインの設定ファイルを生成しません。

※ すでに存在する `~/.claude/skills` などのディレクトリは、Home Manager により `.bak` 拡張子が付与されて自動退避されます。

### アンインストール手順

設定を解除する場合は、以下の手順を実施します。

1. `use_ai_agents.star` の `requires` から `agent_config` を除外します。
2. ユーザーファイルから `agent_config_root`（および自動 clone を利用している場合は `agent_config_repo`）を削除します。圧縮プラグインの設定も解除する場合は `agent_compression` もあわせて削除してください。
3. switch を実行します。

switch 実行によって削除されるのは、Home Manager が管理するシンボリックリンクと `agent-sync` の path unit のみです。生成済みの起動コマンド、Codex プロファイルのリンク、および `~/.claude/settings.json` に反映された設定値は残存します。
これらを含めて完全に削除する場合は、Claude Code と Codex を終了したうえで以下のクリーンアップコマンドを実行してください（`<root>` は解除した `agentConfigRoot` のパスに置き換えます）。

```sh
rm -r ~/.local/share/agent-launchers
find ~/.codex -maxdepth 1 -type l -name '*.config.toml' -lname '<root>/codex/*'          # 削除対象の確認
find ~/.codex -maxdepth 1 -type l -name '*.config.toml' -lname '<root>/codex/*' -delete
(umask 077; jq --slurpfile p ~/.local/state/agent-sync/claude-managed-paths.json 'delpaths($p[0])' \
  ~/.claude/settings.json > ~/.claude/settings.json.new)
mv ~/.claude/settings.json.new ~/.claude/settings.json
rm -r ~/.local/state/agent-sync
```

## マシン固有の指示

自分用サーバで作業するホスト（spin713）では、負荷の大きい処理をサーバ側で実行するよう、Claude Code と Codex のシステム層に指示を設定します。
指示の本文は [agent_offload_notes.star](../../config/elements/agent_offload_notes.star) に定義されています。本文内に記載される接続名は、自分用サーバ上で `serve_workspace` を稼働させているユーザー情報から `find_home_server` により動的に導出されます。

1. ユーザー定義（`[[users]]`）の `purposes` に `program_on_home_server` を追加します（`program_on_home_server` は、AI エージェント用の `use_ai_agents` を内包する `programming` と、`agent_offload_notes` を `requires` に含みます）。
2. switch を実行します。本文は Nix store を経由して配置されるため、`agent_offload_notes.star` の内容を編集するたびに switch が必要です。

設定内容は、Claude Code では `/etc/claude-code/CLAUDE.md`、Codex では `/etc/codex/config.toml` の `developer_instructions` 項目として反映されます。
※ 本機能は NixOS ホストのみが対象であり、macOS のスタンドアロン Home Manager 環境には適用されません。

反映確認手順:

- **Claude Code**: `/context` コマンドを実行し、**Memory files** に `/etc/claude-code/CLAUDE.md` が含まれていることを確認します。
- **Codex**: `grep developer_instructions /etc/codex/config.toml` で内容が書き出されていることを確認したうえで、対話セッションで「このマシン固有の指示を要約して」と質問し、期待どおりの応答が得られるか確認します。

## Claude の同期方針

設定リポジトリの `claude/settings.json` に定義された各キーは、`agent-sync` により `~/.claude/settings.json` へ反映されます。Linux 環境ではファイルを保存すると自動で同期が実行され、次回のセッションから適用されます。

- **上書き動作**: 設定リポジトリ側で定義されているキーの値は、設定リポジトリの内容で上書きされます。CLI やアプリ内から一時的に変更しても次回同期時にリポジトリの値へ復元され、前回同期時からの変更が検知された場合は警告が出力されます。
- **オブジェクト型キーのマージ**: オブジェクト型の値を持つキー（`enabledPlugins`、`env`、`hooks` など）は、配下のプロパティ単位でマージされます。そのため、`/plugin` コマンドなどで一時的に追加した「リポジトリ側に存在しないキー」はそのまま保持されます。
- **キーの削除**: 設定リポジトリ側からキーを削除すると、`~/.claude/settings.json` 側からも該当キーが削除されます。なお、設定リポジトリ側で一度も定義されていないキー（`model` や `theme` など）には影響しません。
- **エラーハンドリング**: いずれかの JSON ファイルが構文エラー等で破損している場合、同期処理は安全に中断され、`~/.claude/settings.json` への書き込みは行われません（switch コマンド自体は失敗せず継続します）。
