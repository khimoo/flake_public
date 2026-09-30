# agents-private（Claude Code と Codex の設定 repo）を使うための設定。clone URL（agentConfigRepo）は
# ここに置かない。置くと sops で id_github を復号する処理が加わり、age 鍵を持たないホストでは
# activation が止まる（docs/architecture/wsl.md）。
{ config, ... }:
{
  local.profile = {
    agentConfigRoot = "${config.home.homeDirectory}/sagyo/agents-private";
    agentProfiles = {
      claude = [
        "opus"
        "fable"
      ];
      codex = [ "astra" ];
    };
  };

  # 日本語のセッションを既定にする。英語でコメントや文書を書くときだけ /caveman で切り替える。
  local.agentCompression = {
    caveman = "off";
    genshijin = "normal";
  };
}
