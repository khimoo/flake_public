# agents-private（Claude Code と Codex の設定 repo）を使うための設定。clone URL（agentConfigRepo）は
# ここに置かない。置くと sops で id_github を復号する処理が加わり、age 鍵を持たないホストでは
# activation が止まる（docs/architecture/wsl.md）。
{ config, ... }:
{
  local.profile = {
    # プロファイル（claude-opus などの起動コマンド）は設定 repo のファイルから agent-sync が作る。
    agentConfigRoot = "${config.home.homeDirectory}/sagyo/agents-private";
  };

  # 日本語のセッションを既定にする。英語でコメントや文書を書くときだけ /caveman で切り替える。
  local.agentCompression = {
    caveman = "off";
    genshijin = "normal";
  };
}
