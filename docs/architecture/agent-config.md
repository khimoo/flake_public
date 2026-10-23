# エージェント設定の設計

使い方: [エージェント設定](../howtouse/agent-config.md)
実装: [claude.nix](../../modules/home-manager/dev/claude.nix)、[codex.nix](../../modules/home-manager/dev/codex.nix)、[agent-sync.nix](../../modules/home-manager/dev/agent-sync.nix)、[agent-instructions.nix](../../modules/nixos/agent-instructions.nix)

## 設定 repo の clone へ out-of-store symlink する

エージェントの設定は private な内容を含むので、公開している flake_public には置けない。
設定 repo を持たない人には何も影響しないように、clone の場所をユーザーの `local.profile.agentConfigRoot`（既定は `null`）から渡し、`null` なら何もしない。
flake_public が設定 repo について知るのは、`shared/`、`claude/`、`codex/` の分け方とファイル名だけにした。

退けた案と理由:

- 設定 repo を flake input にする: private な input があると、アクセス権のない人の `nix flake update` と `nix flake check` が失敗する。skill は頻繁に編集するので、編集のたびに commit、`nix flake update`、switch が要るのも合わない
- `~/.claude` を丸ごと symlink する: Claude Code が履歴やキャッシュを書き込むディレクトリなので、管理したいカテゴリだけをディレクトリごと張る。Claude Code が読む既知のカテゴリは最初から全部張り、repo にまだないものは dangling のままにする（Claude Code には「設定なし」に見える）
- 読み取り専用の `settings.json` や `config.toml` を生成する: `/model` などのアプリからの書き込みが失敗する

## 設定 repo を `shared/`、`claude/`、`codex/` に分ける

どちらのエージェントが読むかで置き場所を決める。

- Claude Code は `AGENTS.md` を読まない。そこで `claude/CLAUDE.md` の先頭で `@../shared/AGENTS.md` を import し、Codex の `~/.codex/AGENTS.md` と同じファイルを読ませる。`@import` の相対パスは、symlink の置き場所ではなく実体のディレクトリを基準に解決される（2026-09-12 に、symlink にした `CLAUDE.md` の両方の候補に別の印を置いて `claude -p` で確かめた）
- Codex 0.153 は `~/.agents/skills/` から Claude Code と同じ形式の `SKILL.md` を読む。`~/.agents/skills` は `codex/skills/` に向け、共有の skill へはそこから相対リンクを張る。Codex 専用の skill は Claude からは見えない
- 共通の指示を repo の直下に置かないのは、Codex が cwd から上の `AGENTS.md` を project の指示としても読むため。直下に置くと、設定 repo を編集するセッションで global と project が同じファイルになる。直下の `AGENTS.md` と `CLAUDE.md` は repo の保守用に使う

## アプリが書き込むファイルは張らない

`~/.codex/config.toml` には、Codex が信頼済みディレクトリや選んだモデルを書き込む（[codex-subagents.md](./codex-subagents.md) で symlink を退けた）。
全マシン共通の設定は `/etc/codex/config.toml`（system 層）に、モデルごとの値はプロファイルに置く。

Codex は `~/.codex/rules/` の `*.rules` を全部読み、承認の「always allow」とネットワークの承認は `default.rules` にだけ追記する（`codex-rs/core/src/exec_policy.rs` の `DEFAULT_POLICY_FILE`、2026-09-12 の main）。
複数の規則に当たると最も厳しい決定が使われる。
そこで人が書く方針だけを `base.rules` として張り、`default.rules` は追跡しない。

`~/.claude/settings.json` も同じ理由で追跡しない（[Claude の方針](#claude-の方針は設定-repo-からユーザー設定へ反映する)）。

## モデルの違いはプロファイルに限る

Claude Code は `--settings <file>` をコマンドラインの層としてユーザー設定に重ね、Codex は `--profile <name>` で `~/.codex/<name>.config.toml` をユーザーの層に重ねる（0.153.4 で `CODEX_HOME` を分けて確かめた。`-c profile=<name>` では読まれない）。
モデルごとに変えたいのは系列と reasoning effort で、どちらも設定値なのでこの層に収まる。指示文は、分ける理由がないのでモデルで分けない。

- 起動は alias ではなく PATH 上の実行ファイルにする。alias とシェル関数は、IDE や他のツールからの起動に適用されない
- Codex の `--profile` は一回しか渡せない（`cannot be used multiple times`）。モデルに依らない private な設定を `base` プロファイルに置く案は成り立たない
- `CLAUDE_CONFIG_DIR` でモデルごとに `~/.claude` を分ける案は、セッションの履歴とプラグインまで分かれるので退けた

## モデル ID を書かず、起動時に系列から版を選ぶ

どの系列（Claude の Opus と Fable、Codex の Astra と sol）を使うかは起動コマンドで選び、系列の中の新しい版は、利用者もエージェントも設定を書き換えずに使う。

Claude Code は `opus`、`fable` のような別名を、インストールされている Claude Code が知る最新のモデルに解決する（2.1.287 の `claude --help`）。プロファイルには別名を書く。

Codex には系列を指す別名がない。0.160.0 の `codex debug models` の ID はどれも版を含み、古いモデルに付く `upgrade` も、新しい版の出ている `gpt-6-sol` で `null` だった。
そこで設定 repo の `codex/launch.py` が起動のたびに一覧を読み、ID の版番号を数値として比べて最新版を選ぶ。

- 一覧の `priority` は使わない。Codex での用途は並び順と既定モデルの選択で（`codex-rs/models-manager/src/manager.rs` の `build_available_models`、tag `rust-v0.160.0`）、新旧の順を保証しない
- ID の形（`gpt-<版>-<系列>`）が変わると候補がなくなり、`codex-<系列>` は起動せずに止まる。そのときは `launch.py` の規則を直す
- 子エージェントのモデルも `-c agents.default_subagent_model=...` で渡す。Codex は spawn でモデルが指定されず、役割の定義にも `model` がなければこの値を使う（`codex-rs/core/src/agent/child_config.rs` と `role.rs`、tag `rust-v0.160.0`）
- 選ぶ処理は sol-handoff の `run.py` も使うので、設定 repo に置く。flake_public は起動コマンドの配線だけを持つ

退けた案と理由:

- 版を固定し、新しい版が出たら通知する: 書き換えの手作業が残る
- 素の `codex` を、モデルを足すラッパーに置き換える: codex-companion や `run.py` も `codex` を呼ぶので、`app-server` のようなサブコマンドにはモデルを渡さない区別を保守し続けることになる

## プロファイルの名簿は設定 repo のファイルから導く

名簿は設定 repo の `claude/profiles/*.json` と `codex/*.config.toml` そのものとし、`agent-sync` が実行時に読んで起動コマンドと Codex のリンクを作る。
flake_public にプロファイル名を並べると、設定 repo にファイルを足すたびに同じ名前を手で書き足すことになる。評価時に設定 repo を読む（flake input にする）と、評価と lock の更新に SSH 鍵が要る。
何をどこへ張るか（`claude.nix`、`codex.nix`）は、ツールの仕様が変わったときにしか変わらないので Nix の `home.file` に残した。

- 起動コマンドは Nix の世代の外に置くので、世代を戻しても戻らない。起動コマンドが指す `claude` と `codex` の store パスは switch のたびに書き直す
- 起動コマンドには生成した印の行を入れ、印のあるファイルだけを後始末で消す。Codex のリンクは、設定 repo の `codex/` を指すものだけを消す
- 名前は英数字と `_`、`-` に限る。shell のメタ文字を含む名前は飛ばす
- 設定 repo の変更を見る path unit は Linux にしかない。macOS では、プロファイル名を足したり消したりしたら switch か `agent-sync` の実行が要る

## マシン固有の指示はシステム層に置く

設定 repo の指示は全マシンで同じファイルなので、マシンによって変わる指示を書く場所がない。
例として spin713 には「メモリや GPU を多く使う処理はまずデスクトップで実行できるか確かめ、できなければフリーズしないか概算してから手元で実行する」という指示が要る（[remote-build.md](./remote-build.md#spin713-では手元でビルドしないmax-jobs--0)）。

NixOS のホスト設定 `local.agentInstructions` から、両方のエージェントのシステム層に同じ本文を書き出す。

- Claude Code: `/etc/claude-code/CLAUDE.md`。公式文書（[How Claude remembers your project](https://code.claude.com/docs/en/memory)、2026-09-24 に参照）が Linux の managed policy の指示ファイルとして挙げるパスで、「Managed policy CLAUDE.md files cannot be excluded」とある
- Codex: `/etc/codex/config.toml` の `developer_instructions`（0.154.0 にこのキーがある）。ユーザーの層とプロファイルはこのキーを設定していないので、system 層の値が使われる

TOML では、テーブルの見出しの後に書いたキーはそのテーブルに入る。
そこで `developer_instructions` は `lib.mkBefore` で `codex.nix` の `[agents]` より前に置き、値は `builtins.toJSON` で TOML の basic string にする。引用符、バックスラッシュ、改行、日本語を含む本文が元に戻ることは `tests/default.nix` で確かめている。
両方のエージェントが実機でこの本文を読むかは、2026-09-24 の時点では確かめていない。

退けた案と理由:

- 共通の `shared/AGENTS.md` に「ホスト名が nixos-spin713 なら」と書く: マシンの事実が flake の外に散らばり、全マシンのエージェントが毎回その条件を読む
- home-manager が書き出したファイルを `claude/CLAUDE.md` から `@import` する: Codex には import がないので `~/.codex/AGENTS.md` を連結して生成することになり、設定 repo の指示を編集しても switch するまで反映されなくなる

代償として、本文は Nix store を経由するので編集のたびに switch が要り、standalone home-manager の環境には入らない。

## Claude の方針は設定 repo からユーザー設定へ反映する

`~/.claude/settings.json` には、Claude Code が `/model`、`/config`、`/plugin` のたびに書き込む。
残したい方針は設定 repo の `claude/settings.json` に置き、`agent-sync` が `~/.claude/settings.json` の同じキーへ反映する。

- 設定 repo にあるキーは設定 repo の値を優先する（ユーザーの判断）。前回の反映の後にアプリの中で変わっていたキーは、警告してから上書きする
- 値がオブジェクトのキーは一段下のキーごとに管理し、利用者が `/plugin` で足したキーを残す。配列は値ごと置き換える
- 前回反映したキーを `~/.local/state/agent-sync/` に記録し、設定 repo から消えたものだけを消す
- どちらかの JSON が壊れていれば反映を止める。switch は止めない
- ユーザー設定は project の設定や `--settings` より優先度が低いので、プロジェクト側の設定で上書きされうる

退けた案と理由:

- `~/.claude/settings.json` を設定 repo へ直接リンクする: アプリの書き込みを、コミットのたびに diff で選り分けることになる
- `/etc/claude-code/managed-settings.json` を設定 repo へのリンクにする: managed settings はマシンの全ユーザーに掛かる組織向けの層で（[設定スコープ](https://code.claude.com/docs/en/settings)）、個人の checkout をマシン全体から参照することになる
- 毎回 `--settings` で重ねる: ラッパーを通さない起動（IDE など）に適用されない

既存の JSON に管理するキーだけを取り込む方式は、公開されている dotfiles でも chezmoi の `modify_` などで使われている。Claude Code に標準の方法はなく、この形はこのリポジトリの判断である。

## 見直す条件

- Claude Code が `AGENTS.md` を直接読むようになったら、`claude/CLAUDE.md` の import は要らない
- Codex がユーザーの層の指示ファイルに include やホスト別のファイルを入れたら、マシン固有の指示を `developer_instructions` から指示ファイルに移す
- Codex がユーザーの層の `config.toml` に include や複数のファイルを入れたら、モデルに依らない private な設定を設定 repo に置ける
- `--profile` を複数回渡せるようになったら、`base` プロファイルの案を考え直す
