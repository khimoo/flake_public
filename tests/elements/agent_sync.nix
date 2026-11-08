{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers)
    home
    activationHome
    users
    hasLauncher
    commandText
    ;
in
{
  agent_sync-contracts =
    (lib.lazyDerivation {
      derivation = (
        # プロファイルの起動コマンドは agent-sync が実行時に作る。設定 repo のないユーザーには入れない。
        assert hasLauncher users.alice "agent-sync";
        assert users.alice.home.activation ? agentSync;
        assert !(hasLauncher users.bob "agent-sync");
        assert !(users.bob.home.activation ? agentSync);
        pkgs.runCommand "agent_sync-contracts" { } ''
          echo "agent_sync contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [ "agent_sync" ];
    };
  # 設定 repo のファイルから起動コマンドと Claude Code の設定を作る agent-sync の動作。
  agent-sync =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "agent-sync"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.bash
              pkgs.jq
            ];
          }
          ''
            python ${../agent-sync.py} ${pkgs.writeText "agent-sync.sh" (commandText "agent-sync")}
            touch "$out"
          ''
      );
    })
    // {
      elements = [ "agent_sync" ];
    };
  # agent-sync の shellcheck。
  agent-sync-package =
    (lib.lazyDerivation {
      derivation = (
        lib.findFirst (
          p: (p.name or "") == "agent-sync"
        ) (throw "agent-sync is not installed") activationHome.config.home.packages
      );
    })
    // {
      elements = [ "agent_sync" ];
    };
}
