# Claude Code のユーザー設定 (~/.claude/) のうち git 管理するものを、設定 repo の
# clone (claudeConfigRoot) へ out-of-store symlink で配線する。
#
# flake_public は公開リポジトリなので、private な設定 repo の固有名や中身には依存しない。
# claudeConfigRoot が null (既定) なら何もしないため、この flake だけを使う人には影響しない。
# 期待するレイアウト: <root>/CLAUDE.md (グローバル指示), <root>/settings.json, <root>/skills/ (skill 群)。
#
# ~/.claude 自体は Claude Code が settings.json や履歴等を書き込む live なディレクトリ
# なので丸ごとは symlink せず、git 管理したいエントリだけを個別に symlink する。
# out-of-store symlink のため、repo 側の編集は rebuild なしで即反映される。
#
# configDirs は Claude Code がユーザー設定を読む既知カテゴリ。各ディレクトリを丸ごと
# symlink するので、配下の skill/agent/command 追加・編集は rebuild なしで即反映される。
# repo にまだ存在しないカテゴリは dangling symlink になるが、Claude Code からは
# 「設定なし」に見えるだけで壊れない。repo 側でそのディレクトリを作った時点で live に
# なるため、Claude Code が全く新しいカテゴリを導入した時以外は switch が要らない。
{ config, settings, lib, ... }:

let
  root = settings.claudeConfigRoot;
  configDirs = [ "skills" "agents" "commands" "output-styles" "hooks" ];
  mkLink = path: config.lib.file.mkOutOfStoreSymlink "${root}/${path}";
in
{
  config = lib.mkIf (root != null) {
    home.file = {
      ".claude/CLAUDE.md".source = mkLink "CLAUDE.md";
      # /config での変更が repo の差分として出るので、マシン固有の値は入れないこと。
      ".claude/settings.json".source = mkLink "settings.json";
    } // builtins.listToAttrs (map (d: {
      name = ".claude/${d}";
      value.source = mkLink d;
    }) configDirs);
  };
}
