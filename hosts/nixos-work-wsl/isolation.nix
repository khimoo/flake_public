# 会社 PC の WSL には、自宅への接続経路を入れない（docs/architecture/wsl.md）。
# 利用目的を足した結果これらが入ったら、黙って入れずに評価を止める。
{ config, ... }:
{
  assertions = [
    {
      assertion = !config.services.openssh.enable;
      message = "nixos-work-wsl: sshd must not run on the company PC (a purpose pulled in ssh_server)";
    }
    {
      assertion = !config.services.tailscale.enable;
      message = "nixos-work-wsl: tailscale must not run on the company PC (a purpose pulled in tailscale, e.g. through find_home_server)";
    }
    {
      assertion = !config.nix.distributedBuilds;
      message = "nixos-work-wsl: builds must not be sent home from the company PC (a purpose pulled in remote_build)";
    }
  ];
}
