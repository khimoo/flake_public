{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) home users rejectsPurpose;
in
{
  agent_links-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert !(users.bob.home.file ? ".claude/CLAUDE.md");
        assert !(users.alice.home.file ? ".claude/settings.json");
        assert !(users.alice.home.file ? ".codex/astra.config.toml");
        # agent_config を選んだ利用者は、配置先（agent_config_root）を必ず書く。
        assert rejectsPurpose "test-agent-url" "x86_64-linux" "has no .agent_config_root attribute";
        assert rejectsPurpose "test-agent-outside" "x86_64-linux"
          "agent_links: mutable checkouts must belong";
        pkgs.runCommand "agent_links-contracts" { } ''
          echo "agent_links contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "agent_links"
        "agent_sync"
      ];
    };
}
