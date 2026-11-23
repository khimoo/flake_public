{ config, lib, pkgs, ... }:
let
  package = pkgs.callPackage ../../../packages/aiboard { };
  profiles = (lib.importJSON ../../../packages/aiboard/agents.json).agents;
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  home = config.home.homeDirectory;
in
{
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
    Unit = { Description = "aiboard ローカル Web UI と住人キュー"; };
    Service = {
      Type = "exec";
      ExecStart = "${package}/bin/aiboard serve --host 127.0.0.1 --port 15280";
      Environment = [ "HERMES_HOME=${home}/.hermes" ];
      KillMode = "mixed";
      TimeoutStopSec = 35;
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
