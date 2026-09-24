# マシン固有のエージェント指示を、Claude Code と Codex のシステム層に書き出す。
# ユーザー層の指示（agentConfigRoot の設定 repo）は全マシン共通の symlink なので、
# ホストによって変わる指示はここから入れる（docs/architecture/agent-config.md）。
{ config, lib, ... }:
let
  instructions = config.local.agentInstructions;
in
{
  options.local.agentInstructions = lib.mkOption {
    type = lib.types.lines;
    default = "";
    description = "Host-specific instructions for Claude Code and Codex on this machine.";
  };

  config = lib.mkIf (instructions != "") {
    # Claude Code は Linux で、管理者用の指示をこのパスから読む。
    environment.etc."claude-code/CLAUDE.md".text = instructions;
    # TOML ではテーブル見出しの後のキーがそのテーブルに入るので、codex.nix の [agents] より前に置く。
    # toJSON の出力は TOML の basic string としても読める（tests/default.nix で確かめている）。
    environment.etc."codex/config.toml".text = lib.mkBefore ''
      developer_instructions = ${builtins.toJSON instructions}
    '';
  };
}
