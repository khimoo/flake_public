# 会社 PC の NixOS-WSL。CLI だけのホストにし、個人の秘密と自宅への経路を持たせない
# （docs/architecture/wsl.md）。
{ config, inputs, settings, ... }:
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
    ../../modules/nixos/base.nix
  ];

  wsl.enable = true;
  wsl.defaultUser = settings.primaryUser;

  local.restrictedHost.enable = true;

  local.claudeManagedSettings = "${
    config.home-manager.users.${settings.primaryUser}.local.profile.agentConfigRoot
  }/claude/managed-settings.json";

  # deploy key を github.com に付けると、会社のアカウントでの SSH 接続も deploy key で認証される。
  # ~/.ssh/config は会社用の設定を手で書けるように Home Manager で管理しない。
  programs.ssh.extraConfig = ''
    Host github-agents-private
      HostName github.com
      User git
      IdentityFile ~/.ssh/id_agents_private
      IdentitiesOnly yes
  '';
}
