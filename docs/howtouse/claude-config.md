# Claude Code ユーザー設定の git 管理

`~/.claude/` のうち git 管理したい設定（グローバル CLAUDE.md と skills 等）を、
別リポジトリの clone へ symlink して管理する。

設計判断は [docs/architecture/claude-config.md](../architecture/claude-config.md) を参照。

## 設定 repo に期待するレイアウト

```
<claudeConfigRoot>/
├── CLAUDE.md        # グローバル指示 (~/.claude/CLAUDE.md になる)
├── skills/          # skill 群 (~/.claude/skills になる)
│   └── <skill-name>/SKILL.md
├── agents/          # subagent 定義 (~/.claude/agents になる)
├── commands/        # カスタム slash command (~/.claude/commands になる)
└── output-styles/   # output style (~/.claude/output-styles になる)
```

`skills` 以外のカテゴリ用ディレクトリは、まだ無ければ作らなくてよい（symlink は
張られるが repo 側が空なら Claude Code からは「設定なし」に見えるだけ）。使いたく
なった時点で repo にそのディレクトリを作れば、**rebuild なしで即 live になる**。

## マシンに挿す手順

1. 設定 repo を任意の場所に clone する
   （NixOS なら [private-repo-clone.md](./private-repo-clone.md) で自動 clone にできる）
2. `flake.nix` の対象ホスト（`mkSystem` / `mkHome` の呼び出し）に clone 先を指定する:

   ```nix
   claudeConfigRoot = "/home/pomu/sagyo/claude-private";
   ```

3. rebuild する（`~/.claude/CLAUDE.md` と各カテゴリディレクトリが symlink になる）

既存の `~/.claude/skills` 等のディレクトリがあった場合は home-manager が `.bak` に退避する。

## 抜く手順

`claudeConfigRoot` の指定を消して rebuild するだけ（既定は `null` = 無効）。
設定 repo を持たない環境・他人の利用では何も起きない。

## 日常運用

- skill / agent / command / output-style の追加・編集は設定 repo 側で直接行う。
  out-of-store symlink なので **rebuild 不要で即反映**される
- 各カテゴリディレクトリ全体が repo への symlink のため、中身は必ず repo 側で作る
  （`~/.claude/skills/` 直下に手でディレクトリを作ると repo に入る）
- 配線済みカテゴリ（`skills` `agents` `commands` `output-styles`）の中身追加は
  switch 不要。switch が要るのは Claude Code が**全く新しいカテゴリ**を導入し、それを
  使い始めるときだけ（その場合は `claude.nix` の `configDirs` に 1 行足す）
- `settings.json` や履歴などは Claude Code が書き込む live なファイルなので管理対象外
