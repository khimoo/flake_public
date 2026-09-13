# エージェント設定（Claude Code / Codex）の git 管理（設計判断）

使い方は [docs/howtouse/agent-config.md](../howtouse/agent-config.md) を参照。
実装: [modules/home-manager/dev/claude.nix](../../modules/home-manager/dev/claude.nix)、
[modules/home-manager/dev/codex.nix](../../modules/home-manager/dev/codex.nix)

## 何を解決するか

Claude Code と Codex CLI のユーザー設定（共通指示、skills、Claude の settings と
output style、Codex の実行ポリシー）は private な内容を含むため flake_public には置けない。
一方で git 管理と複数マシンでの共有はしたい。
flake_public は名目上誰でも使える公開リポジトリなので、private な設定は
**抜き差し可能**（持っていない人には一切影響しない）である必要がある。

二つのハーネスを併用するので、指示と skills を一箇所に持ち、両方がそれを読む形にする。

## 採った方式: パス注入 + out-of-store symlink

- 設定 repo の clone 先は、そのユーザーの `local.profile.agentConfigRoot`（既定 null）から注入する。
  `modules/home-manager/profile.nix` が型を定義し、別ユーザーの home 配下は拒否する。
- モジュールは `null` なら no-op。非 null なら `claude.nix` が `~/.claude/` の各エントリを、
  `codex.nix` が `~/.codex/AGENTS.md` `~/.agents/skills` `~/.codex/rules/base.rules` を
  `mkOutOfStoreSymlink` で clone へ張る

flake_public 側が設定 repo について知るのはレイアウト規約（`shared/` `claude/` `codex/` の
三分割と各ファイル名）だけで、repo の固有名・URL・中身には依存しない。

## repo を `shared/` `claude/` `codex/` に分ける理由

各ファイルを「誰が読むか」で置く。

- `shared/AGENTS.md`: Codex は `~/.codex/AGENTS.md` を global 指示として読み、Claude Code は
  `AGENTS.md` を読まない（"Claude Code reads CLAUDE.md, not AGENTS.md"）。そこで
  `claude/CLAUDE.md` の先頭で `@../shared/AGENTS.md` を import し、両方が同じファイルを読む。
  `@import` の相対パスは symlink の置き場所ではなく実体のディレクトリを基準に解決される
  （2026-09-12 に実測。project 層の `CLAUDE.md` を symlink にし、両方の候補に別のマーカーを
  置いて `claude -p` に答えさせた）
- `shared/skills/`: Codex 0.153 は `~/.agents/skills/` から Claude Code と同じ `SKILL.md`
  （`name` と `description` の frontmatter）を読み、description に合えば暗黙に起動する。
  Claude は `~/.claude/skills` から直接参照する。Codex は `~/.agents/skills` を
  `codex/skills/` に向け、そこから共有スキルへ相対リンクを張る。Codex 専用スキルは
  `codex/skills/` のみに置くため、Claude には公開されない
- `claude/`: Claude Code だけが読むもの。`settings.json` と `hooks/` `output-styles/` `agents/` `commands/`
- `codex/rules/base.rules`: Codex だけが読むもの

共通指示を repo 直下に置かないのは、Codex が cwd から上の `AGENTS.md` を project 指示としても
読むため。直下に置くと repo 自体を編集するセッションで global と project が同じファイルになり、
repo 保守用の指示を書く場所がなくなる。直下の `AGENTS.md` / `CLAUDE.md` は repo 保守用に充てる。

## Codex の live ファイルを張らない理由

`~/.codex/config.toml` は Codex が信頼済みディレクトリ（`[projects."<絶対パス>"]`）、
TUI で選んだモデル、NUX カウンタを書き込むアプリケーション状態の置き場で、
[codex-subagents.md](./codex-subagents.md) で symlink 方式を退けた。
全マシン共通の宣言は `/etc/codex/config.toml`（system 層）、モデルごとの値は
プロファイル層 `~/.codex/<name>.config.toml`（`codex --profile <name>`）に置く。

`~/.codex/rules/` は事情が違う。Codex は `rules/` 配下の `*.rules` を全部読み、
承認プロンプトの「always allow」とネットワーク承認は `default.rules` にだけ追記する
（`codex-rs/core/src/exec_policy.rs` の `DEFAULT_POLICY_FILE` と `default_policy_path`、
2026-09-12 の main）。複数一致は最も厳しい決定が勝つ。そこで人が書く方針を `base.rules` として
張り、`default.rules` は live のまま追跡しない。`base.rules` の `forbidden` / `prompt` を
`default.rules` の `allow` が緩めることはない。

## モデル別の差分をプロファイルに限る理由

Claude Code は `--settings <file>` をコマンドライン層としてユーザー設定の上に重ね、Codex は
`--profile <name>` で `~/.codex/<name>.config.toml` をユーザー層の上に重ねる（0.153.4 で
`CODEX_HOME` を隔離して実測。`-c profile=<name>` では読まれない）。モデルごとに変えたい値は
model と reasoning effort で、どちらも設定値なのでこの層に収まる。指示文はモデルで分けない。
分ける必要がいまのところ無く、分けると同じ規約を二重に持つことになるため。

起動は alias ではなく `writeShellScriptBin` で作る PATH 上の実行ファイルにする。alias と
シェル関数は対話シェルの外（IDE や他ツールからの起動）で効かない。名前は
`local.profile.agentProfiles` で宣言する。Codex のプロファイルは `CODEX_HOME` 直下の
ファイルとして探されるため名前ごとに symlink が要り、その列挙から起動ファイルも機械的に
出せる。宣言は空が既定で、名前の重複と shell のメタ文字は型と assertion で弾く。

`--profile` は一回しか渡せない（`cannot be used multiple times`）ので、モデル非依存で
private な Codex 設定を base プロファイルに置く案は成立しない。

## 検討して退けた案

### 設定 repo を flake input にする（zettelkasten 方式）

zettelkasten（同期の仕組み）は flake input（`github:khimoo/zettelkasten-workflow`）だが、
エージェント設定には合わない:

- **公開利用性**: private repo を flake input にすると、アクセス権のない人は
  `nix flake update` / `nix flake check` で失敗する。zettelkasten は仕組みを
  public repo（`github:`, https 取得）に分割してこれを回避した（ノート本文だけ別の
  private repo に残す）。エージェント設定 repo は public 化する動機のない純粋な private
  コンテンツなので、input にすると回避策のない形でこの制約を持ち込むことになる
- **編集サイクル**: skills は頻繁に編集する「生きた設定」で、input 経由の store コピーだと
  編集のたびに commit + `nix flake update` + rebuild が必要になる。
  neovim 設定が out-of-store symlink である理由と同じ
- **input が提供する価値がない**: zettelkasten input は同期スクリプトや home-manager
  モジュール（仕組み）を提供するから input である意味がある。エージェント設定 repo は
  純粋なコンテンツなので、パスさえ分かれば良い

### `~/.claude` を丸ごと symlink する

`~/.claude` は Claude Code 自身が `settings.json`・履歴・キャッシュ等を書き込む
live なディレクトリのため、git 管理したいエントリだけを個別に symlink する。カテゴリは
ディレクトリ丸ごと symlink し、repo をそのカテゴリの唯一の所有者とする（個別 skill/agent
ごとの列挙を Nix 側に持たない）。

Claude Code がユーザー設定を読むカテゴリ（`skills` `agents` `commands` `output-styles` `hooks`）は
ツール側で決まった小さな固定集合なので、既知カテゴリを最初から全部張っておく。repo に
まだ存在しないカテゴリは dangling symlink になるが（Claude Code からは「設定なし」に
見えるだけで無害）、repo 側でそのディレクトリを作った瞬間に live になる。switch が要るのは
ツールが**未知の新カテゴリ**を導入したときだけに限定される。

### `settings.json` を `--settings` で毎回重ねる（live を追跡しない）

`claude --settings <file>` はコマンドライン層としてユーザー設定の上に重なるが、ラッパーを
通さない起動（IDE、他ツールからの呼び出し）には効かず、`/model` の保存先が profile に
上書きされて効かなく見える。live を symlink する現行方式のほうが、rules の `default.rules`
と同じ「アプリの書き戻しを diff で見て選別する」運用に揃う。

### home-manager が生成した読み取り専用の `settings.json` / `config.toml`

`/model` `/config` や Codex 側の書き込みが失敗する。

### Codex の共通設定を `base` プロファイルにして常に `--profile base`

`--profile` が一回しか渡せないためモデル別プロファイルと両立しない。全マシン共通で
public に書ける設定は system 層、private でモデル非依存の設定が必要になったら各プロファイルに
重複して書く。

### 起動を alias にする、または private repo 内のラッパースクリプトにする

alias は対話シェルの外で効かない。private repo にラッパーを置くと起動の仕組みが repo 側に
漏れ、flake_public が「レイアウト規約だけを知る」線を越える。

### `CLAUDE_CONFIG_DIR` でモデルごとに `~/.claude` を分ける

settings と一緒にセッション履歴と plugins の実体も分かれる。変えたい値が model と effort だけ
なら過剰。

### skills を `<repo>/.agents/skills` に置いて Codex の project 層でも拾わせる

global の配線で全プロジェクトに効いているので不要。同じ skill が global と project の
両方で見つかったときの扱いを前提にしない。

## トレードオフ

- clone が無い環境で `agentConfigRoot` を指定すると symlink が dangling になる
  （「設定なし」に見えるだけで壊れはしない）。指定は clone がある
  ホストに限る運用
- レイアウト規約（`shared/` `claude/` `codex/` と各ファイル名）は flake_public と設定 repo の
  間の暗黙の契約。既知カテゴリは列挙済みなので日常の追加では触らないが、
  ツールが未知の新カテゴリを導入した場合はモジュールに 1 行足す必要がある
- `~/.codex/rules/` に `base.rules` と `default.rules` が同居するため、どの行がどちらに
  あるかは人が見て移す。自動化はしない
- プロファイルは既定を選ぶだけで、モデルを固定しない。`claude --resume` は transcript のモデルを
  優先し、Codex は project 層と `-c` フラグがプロファイルより優先される
- プロファイル名の追加・削除は switch を要する（中身の編集は要しない）

## 見直す条件

- Claude Code が `AGENTS.md` を直接読むようになったら `claude/CLAUDE.md` の import は不要になる
- Codex がユーザー層の `config.toml` に include や複数ファイルを導入したら、モデル非依存の
  private 設定を repo に置けるようになる
- `--profile` を複数回渡せるようになったら `base` プロファイル案を再検討する

## Claudeの設定更新に対応する直接リンク

`settings.json`だけは`home.file`の世代リンクを使わず、
activationで設定checkoutへ直接リンクする。2026-09-13にClaudeの
プラグイン導入で、Nix store内に一時ファイルを作ろうとしてEROFSに
なることを確認した。直接リンクなら原子更新の一時ファイルもcheckout内に置ける。

Linux/Darwinともに同じ処理を使い、dry-runでは書き込まない。
既存の通常ファイルは上書きせずエラーにする。中断でリンクが欠けても
再activationで修復できる。Nix世代のrollbackで設定本文は戻らない。
`agentConfigRoot`を無効化するときは、直接リンクした
`~/.claude/settings.json`も手動で外す（他のリンクはHome Managerが管理する）。
