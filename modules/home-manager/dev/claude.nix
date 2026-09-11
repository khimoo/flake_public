# Claude Code のユーザー設定 (~/.claude/) のうち git 管理するものを、エージェント設定 repo の
# clone (agentConfigRoot) へ out-of-store symlink で配線する。Codex 側は codex.nix。
#
# flake_public は公開リポジトリなので、private な設定 repo の固有名や中身には依存しない。
# agentConfigRoot が null (既定) なら何もしないため、この flake だけを使う人には影響しない。
# 期待するレイアウト:
#   <root>/claude/CLAUDE.md, settings.json, hooks/, output-styles/, agents/, commands/   Claude Code だけが読む
#   <root>/shared/skills/                                                              Codex と共有
#
# ~/.claude 自体は Claude Code が settings.json や履歴等を書き込む live なディレクトリ
# なので丸ごとは symlink せず、git 管理したいエントリだけを個別に symlink する。
# out-of-store symlink のため、repo 側の編集は rebuild なしで即反映される。
#
# claudeDirs は Claude Code がユーザー設定を読む既知カテゴリのうち Claude 固有のもの。
# 各ディレクトリを丸ごと symlink するので、配下の agent/command 追加・編集は rebuild なしで
# 即反映される。repo にまだ存在しないカテゴリは dangling symlink になるが、Claude Code からは
# 「設定なし」に見えるだけで壊れない。repo 側でそのディレクトリを作った時点で live に
# なるため、Claude Code が全く新しいカテゴリを導入した時以外は switch が要らない。
#
# skills は Codex と同じ SKILL.md 形式なので実体を一つにし、~/.claude/skills と
# ~/.agents/skills (codex.nix) の両方から <root>/shared/skills を指す。
{ config, lib, ... }:

let
  root = config.local.profile.agentConfigRoot;
  claudeDirs = [ "agents" "commands" "output-styles" "hooks" ];
  mkLink = path: config.lib.file.mkOutOfStoreSymlink "${root}/${path}";
in
{
  config = lib.mkIf (root != null) {
    home.file = {
      ".claude/CLAUDE.md".source = mkLink "claude/CLAUDE.md";
      # /config での変更が repo の差分として出るので、マシン固有の値は入れないこと。
      ".claude/settings.json".source = mkLink "claude/settings.json";
      ".claude/skills".source = mkLink "shared/skills";
    } // builtins.listToAttrs (map (d: {
      name = ".claude/${d}";
      value.source = mkLink "claude/${d}";
    }) claudeDirs);
  };
}
