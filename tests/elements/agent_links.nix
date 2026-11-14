{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) home users rejectsPurposeWithOwner;
in
{
  agent_links-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert !(users.bob.home.file ? ".claude/CLAUDE.md");
        assert !(users.alice.home.file ? ".claude/settings.json");
        assert !(users.alice.home.file ? ".codex/astra.config.toml");
        # agent_config を使うなら、持ち主の値に配置先（agent_config_root）を必ず書く。
        assert rejectsPurposeWithOwner ''
          agent_config_repo = "git@example.org:test/config.git"
        '' "test-agents" "x86_64-linux" "has no .agent_config_root attribute";
        assert rejectsPurposeWithOwner ''
          agent_config_root = "../another-user/config"
        '' "test-agents" "x86_64-linux" "agent_links: mutable checkouts must belong";
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
