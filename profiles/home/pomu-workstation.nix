{ config, lib, ... }:
let
  work = "${config.home.homeDirectory}/sagyo";
in
{
  imports = [
    ./pomu.nix
    ./pomu-agents.nix
  ];
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
    agentConfigRepo = "git@github.com:khimoo/agents-private.git";
    vaultSkeletonRepo = "${work}/zettelkasten-workflow";
    vaultSkeletonRepoUrl = "git@github.com:khimoo/zettelkasten-workflow.git";
    llmWikisRoot = "${work}/llm-wikis";
    llmWikisRepoUrl = "git@github.com:khimoo/llm-wikis.git";
  };

  # 素のキーは us と同じで、右 Alt（AltGr）との組み合わせでアクセント付きの文字とデッドキーを打つ。
  # デスクトップの FreeRDP は、右 Alt が AltGr であることを前提に、右 Alt の直後だけキーボードを掴む（docs/architecture/windows-vm.md）。
  dconf.settings."org/gnome/desktop/input-sources".sources = [
    (lib.hm.gvariant.mkTuple [
      "xkb"
      "us+altgr-intl"
    ])
  ];
}
