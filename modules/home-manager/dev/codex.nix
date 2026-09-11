# Codex CLI のユーザー設定 (~/.codex/, ~/.agents/) のうち git 管理するものを、エージェント設定
# repo の clone (agentConfigRoot) へ out-of-store symlink で配線する。Claude Code 側は claude.nix。
#
# 張るもの:
#   ~/.codex/AGENTS.md         <- <root>/shared/AGENTS.md        全プロジェクト共通の指示。
#                                                               Claude Code は claude/CLAUDE.md の @import で同じファイルを読む
#   ~/.agents/skills           <- <root>/shared/skills           Codex が読む skills。~/.claude/skills と同じ実体
#   ~/.codex/rules/base.rules  <- <root>/codex/rules/base.rules  人が書く実行ポリシー
#
# 張らないもの:
#   ~/.codex/config.toml          Codex が信頼済みディレクトリ・選択中モデル・TUI のカウンタを書き込む
#                                 live なファイル (docs/architecture/codex-subagents.md)。宣言したい共通設定は
#                                 /etc/codex/config.toml (modules/nixos/codex.nix)、モデル別の値は
#                                 ~/.codex/<name>.config.toml (codex -p <name>) に置く。
#   ~/.codex/rules/default.rules  承認プロンプトの「always allow」とネットワーク承認が追記する live なファイル
#                                 (codex-rs/core/src/exec_policy.rs の default_policy_path)。
#
# rules/ 配下の *.rules は全部読まれ、複数一致は最も厳しい決定 (forbidden > prompt > allow) が
# 勝つので、base.rules の forbidden / prompt を default.rules の allow が緩めることはない。
# ~/.codex/rules/ 自体は default.rules が同居する通常ディレクトリのままにし、base.rules だけを張る。
{ config, lib, ... }:

let
  root = config.local.profile.agentConfigRoot;
  mkLink = path: config.lib.file.mkOutOfStoreSymlink "${root}/${path}";
in
{
  config = lib.mkIf (root != null) {
    home.file = {
      ".codex/AGENTS.md".source = mkLink "shared/AGENTS.md";
      ".agents/skills".source = mkLink "shared/skills";
      ".codex/rules/base.rules".source = mkLink "codex/rules/base.rules";
    };
  };
}
