# Claude Code のユーザー設定 (~/.claude/) のうち git 管理するものを、設定 repo の
# clone (claudeConfigRoot) へ out-of-store symlink で配線する。
#
# flake_public は公開リポジトリなので、private な設定 repo の固有名や中身には依存しない。
# claudeConfigRoot が null (既定) なら何もしないため、この flake だけを使う人には影響しない。
# 期待するレイアウト: <root>/CLAUDE.md (グローバル指示), <root>/skills/ (skill 群)。
#
# ~/.claude 自体は Claude Code が settings.json や履歴等を書き込む live なディレクトリ
# なので丸ごとは symlink せず、git 管理したいエントリだけを個別に symlink する。
# out-of-store symlink のため、repo 側の編集は rebuild なしで即反映される。
{ config, settings, lib, ... }:

let
  root = settings.claudeConfigRoot;
in
{
  config = lib.mkIf (root != null) {
    home.file.".claude/CLAUDE.md".source =
      config.lib.file.mkOutOfStoreSymlink "${root}/CLAUDE.md";
    home.file.".claude/skills".source =
      config.lib.file.mkOutOfStoreSymlink "${root}/skills";
  };
}
