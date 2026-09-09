# Claude Code ユーザー設定の git 管理

`~/.claude/` のうち git 管理したい設定（グローバル CLAUDE.md と skills 等）を、
別リポジトリの clone へ symlink して管理する。

設計判断は [docs/architecture/claude-config.md](../architecture/claude-config.md) を参照。

## 設定 repo に期待するレイアウト

```
<claudeConfigRoot>/
├── settings.json    # 共有する設定（マシン固有値を入れない）
├── hooks/           # hookスクリプト（任意）
├── CLAUDE.md        # グローバル指示 (~/.claude/CLAUDE.md になる)
├── skills/          # skill 群 (~/.claude/skills になる)
│   └── <skill-name>/SKILL.md
├── agents/          # subagent 定義 (~/.claude/agents になる)
├── commands/        # カスタム slash command (~/.claude/commands になる)
└── output-styles/   # output style (~/.claude/output-styles になる)
```

カテゴリ用ディレクトリは、まだ無ければ作らなくてよい（symlink は
張られるが repo 側が空なら Claude Code からは「設定なし」に見えるだけ）。使いたく
なった時点で repo にそのディレクトリを作れば、**rebuild なしで即 live になる**。

## マシンに挿す手順

1. 設定 repo を任意の場所に clone する
   （NixOS なら [private-repo-clone.md](./private-repo-clone.md) で自動 clone にできる）
2. 対象ユーザーのhomeモジュール（既存2台では `profiles/home/pomu-workstation.nix`）に clone 先を指定する:

   ```nix
   local.profile.claudeConfigRoot = "/home/pomu/sagyo/claude-private";
   ```

3. rebuild する（`~/.claude/CLAUDE.md` と各カテゴリディレクトリが symlink になる）

既存の `~/.claude/skills` 等のディレクトリがあった場合は home-manager が `.bak` に退避する。

## 抜く手順

`local.profile.claudeConfigRoot` と、自動cloneしている場合は `local.profile.claudeConfigRepo` の指定を両方外してrebuildする（既定null）。URLだけ残す設定は評価時に拒否される。
設定 repo を持たない環境・他人の利用では何も起きない。

## 日常運用

- skill / agent / command / output-style の追加・編集は設定 repo 側で直接行う。
  out-of-store symlink なので **rebuild 不要で即反映**される
- 各カテゴリディレクトリ全体が repo への symlink のため、中身は必ず repo 側で作る
  （`~/.claude/skills/` 直下に手でディレクトリを作ると repo に入る）
- 配線済みカテゴリ（`skills` `agents` `commands` `output-styles` `hooks`）の中身追加は
  switch 不要。switch が要るのは Claude Code が**全く新しいカテゴリ**を導入し、それを
  使い始めるときだけ（その場合は `claude.nix` の `configDirs` に 1 行足す）
- `settings.json` は管理対象。`~/.claude/settings.json` はcheckoutへのsymlinkで、アプリからの編集も共有repoの差分になる。
- `CLAUDE.md` と `settings.json` はcheckoutに用意する。カテゴリディレクトリは任意。履歴・認証情報・キャッシュは管理対象外。
- マシン固有値は共有 `settings.json` に入れない。プロジェクト固有のローカル値は各プロジェクトの `.claude/settings.local.json`、一時的な変更は起動引数を使う。マシン全体の設定を独立させたい場合は、そのユーザーでsymlink管理を外して手動管理する。
- liveな設定はNix世代のロールバックでは戻らない。設定repoのGit履歴で復元する。

Claudeの[設定スコープ](https://code.claude.com/docs/en/settings)も参照。
