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
  ai_agents-contracts =
    (lib.lazyDerivation {
      derivation = (
        # developer_instructions が [agents] のテーブルに入らず、エスケープも崩れないこと。
        assert
          let
            instructions = "一行目 \"quoted\" back\\slash\n二行目\n";
            host = agentHost "test-agent-instructions";
          in
          (codexConfig host).developer_instructions == instructions
          && (codexConfig host).agents.enabled == false
          && host.environment.etc."claude-code/CLAUDE.md".text == instructions;
        assert !((agentHost "test-agent-empty").environment.etc ? "claude-code/CLAUDE.md");
        assert !(codexConfig (agentHost "test-agent-empty") ? developer_instructions);
        pkgs.runCommand "ai_agents-contracts" { } ''
          echo "ai_agents contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [ "ai_agents" ];
    };
}
