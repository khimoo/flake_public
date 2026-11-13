{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) agentHost codexConfig;
in
{
  codex_policy-contracts =
    (lib.lazyDerivation {
      derivation = (
        # 自分用サーバで作業する機体では、重い処理を自分用サーバに任せる指示が、Claude Code と Codex の両方に同じ本文で入る。
        # developer_instructions が [agents] のテーブルに入らず、改行やバッククォートも崩れないこと。
        assert
          let
            host = agentHost "test-agent-instructions";
            instructions = host.environment.etc."claude-code/CLAUDE.md".text;
          in
          (codexConfig host).developer_instructions == instructions
          && lib.hasInfix "ssh desktop-ts" instructions
          && (codexConfig host).agents.enabled == false;
        assert !((agentHost "test-agent-empty").environment.etc ? "claude-code/CLAUDE.md");
        assert !(codexConfig (agentHost "test-agent-empty") ? developer_instructions);
        pkgs.runCommand "codex_policy-contracts" { } ''
          echo "codex_policy contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "agent_offload_notes"
        "codex_policy"
      ];
    };
}
