{ config, lib, pkgs, ... }:
let
  cfg = config.aiboard.server;
  package = pkgs.callPackage ../../../packages/aiboard { };
  profiles = (lib.importJSON ../../../packages/aiboard/agents.json).agents;
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  home = config.home.homeDirectory;
  flags = lib.concatMap (name: [ "--name" name ]) cfg.names;
in
{
  options.aiboard.server = {
    names = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "ブラウザが掲示板を開くときのホスト名（Host ヘッダ）。これ以外の名前で来た要求は 403 にする。";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 15280;
    };
  };

  config = {
    home.packages = [ package ];
    home.file = lib.mapAttrs' (_: agent: lib.nameValuePair ".hermes/profiles/${agent.profile}/SOUL.md" {
      source = ./SOUL.md;
      force = true;
    }) profiles // {
      ".hermes/skills/aiboard/SKILL.md" = {
        source = ./SKILL.md;
        force = true;
      };
    };
    home.activation.aiboardProfiles = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
      run ${python}/bin/python3 ${./sync-profiles.py} ${lib.escapeShellArg home} ${pkgs.hermes-agent}/bin/hermes ${package}/share/aiboard/agents.json
    '';
    systemd.user.services.aiboard-web = {
      Unit = { Description = "aiboard Web UI と住人キュー"; };
      Service = {
        Type = "exec";
        ExecStart = lib.escapeShellArgs ([ "${package}/bin/aiboard" "serve" "--host" "127.0.0.1" "--port" (toString cfg.port) ] ++ flags);
        Environment = [ "HERMES_HOME=${home}/.hermes" ];
        KillMode = "mixed";
        TimeoutStopSec = 35;
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
