{ config, ... }:
let
  work = "${config.home.homeDirectory}/sagyo";
in
{
  imports = [ ./pomu.nix ];
  local.profile = {
    features = {
      gui = true;
      gnome = true;
      ime = true;
      audio = true;
      referenceSync = true;
      zettelkastenSync = true;
      obsidian = true;
    };
    lanSsh = true;
    zettelkastenRoot = "${work}/zettelkasten";
    zettelkastenRepoUrl = "git@github.com:khimoo/zettelkasten.git";
    agentConfigRoot = "${work}/agents-private";
    agentConfigRepo = "git@github.com:khimoo/agents-private.git";
    agentProfiles = {
      claude = [
        "opus"
        "fable"
      ];
      codex = [ "astra" ];
    };
    vaultSkeletonRepo = "${work}/zettelkasten-workflow";
    vaultSkeletonRepoUrl = "git@github.com:khimoo/zettelkasten-workflow.git";
    llmWikisRoot = "${work}/llm-wikis";
    llmWikisRepoUrl = "git@github.com:khimoo/llm-wikis.git";
  };
}
