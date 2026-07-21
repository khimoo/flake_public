# Claude Code ユーザー設定の git 管理（設計判断）

使い方は [docs/howtouse/claude-config.md](../howtouse/claude-config.md) を参照。
実装: [modules/home-manager/dev/claude.nix](../../modules/home-manager/dev/claude.nix)

## 何を解決するか

Claude Code のユーザー設定（グローバル CLAUDE.md・skills）は private な内容を含むため
flake_public には置けない。一方で git 管理と複数マシンでの共有はしたい。
flake_public は名目上誰でも使える公開リポジトリなので、private な設定は
**抜き差し可能**（持っていない人には一切影響しない）である必要がある。

## 採った方式: パス注入 + out-of-store symlink

- 設定 repo の clone 先を `claudeConfigRoot`（既定 `null`）として `mkSystem` / `mkHome` の
  引数から `settings` 経由で注入する。`flakeRoot` / `zettelkastenRoot` と同じ慣習
- モジュールは `null` なら no-op。非 null なら `~/.claude/CLAUDE.md` と `~/.claude/skills` を
  `mkOutOfStoreSymlink` で clone へ張る

flake_public 側が設定 repo について知るのはレイアウト規約
（`CLAUDE.md` + `skills/`、`~/.claude` の構造をそのまま鏡写し）だけで、
repo の固有名・URL・中身には依存しない。

## 検討して退けた案: private repo を flake input にする（zettelkasten 方式）

zettelkasten は git+ssh の flake input だが、claude 設定には合わない:

- **公開利用性**: private な git+ssh input が増えると、アクセス権のない人は
  `nix flake update` / `nix flake check` で失敗する。zettelkasten で既に一箇所
  妥協しているが、これ以上増やさない
- **編集サイクル**: skills は頻繁に編集する「生きた設定」で、input 経由の store コピーだと
  編集のたびに commit + `nix flake update` + rebuild が必要になる。
  neovim 設定が out-of-store symlink である理由と同じ
- **input が提供する価値がない**: zettelkasten input は同期スクリプトや home-manager
  モジュール（仕組み）を提供するから input である意味がある。claude 設定 repo は
  純粋なコンテンツなので、パスさえ分かれば良い

## `~/.claude` を丸ごと symlink しない理由

`~/.claude` は Claude Code 自身が `settings.json`・履歴・キャッシュ等を書き込む
live なディレクトリのため、git 管理したいエントリ（`CLAUDE.md`, `skills`）だけを
個別に symlink する。逆に `skills` はディレクトリ丸ごと symlink し、repo を
skills の唯一の所有者とする（個別 skill ごとの列挙を Nix 側に持たない）。

## トレードオフ

- clone が無い環境で `claudeConfigRoot` を指定すると symlink が dangling になる
  （Claude Code からは「設定なし」に見えるだけで壊れはしない）。指定は clone がある
  ホストに限る運用
- レイアウト規約（`CLAUDE.md` + `skills/`）は flake_public と設定 repo の間の暗黙の契約。
  `agents/` や `commands/` など管理対象を増やす場合はモジュールに 1 行足す必要がある
