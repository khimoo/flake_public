# 会社 PC のように、個人の秘密と自宅への経路を置いてはいけないホストの制限。
# import しないだけでは制限していることが設定から読めず、後から足しても評価が通るので、
# 有効なホストでは破る構成を assertion で止める（docs/architecture/wsl.md）。
{ config, lib, ... }:
let
  cfg = config.local.restrictedHost;
  users = config.home-manager.users;
  forbidUser =
    what: pred:
    lib.mapAttrsToList (name: user: {
      assertion = !(pred user);
      message = "local.restrictedHost: Home Manager user `${name}` must not have ${what} on a restricted host (docs/architecture/wsl.md).";
    }) users;
in
{
  options.local.restrictedHost.enable = lib.mkEnableOption "the restrictions for a company-managed machine: no personal secrets, SSH keys, git identity, inbound SSH, tailnet or remote builders";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.services.openssh.enable;
        message = "local.restrictedHost: inbound SSH (services.openssh) must stay disabled on a restricted host (docs/architecture/wsl.md).";
      }
      {
        assertion = !config.services.tailscale.enable;
        message = "local.restrictedHost: the tailnet (services.tailscale) must stay disabled on a restricted host (docs/architecture/wsl.md).";
      }
      {
        assertion = config.nix.buildMachines == [ ] && !config.nix.distributedBuilds;
        message = "local.restrictedHost: remote builders must not be configured on a restricted host (docs/architecture/wsl.md).";
      }
    ]
    ++ forbidUser "secrets to decrypt (local.profile.secrets / sshKeys)" (
      u: u.local.profile.secrets != [ ] || u.local.profile.sshKeys != [ ]
    )
    ++ forbidUser "the shared LAN key (local.profile.lanSsh)" (u: u.local.profile.lanSsh)
    ++ forbidUser "automatic private repo clones (local.profile.privateRepos)" (u: u.local.profile.privateRepos != [ ])
    # local.profile を通さず programs.git に直接書いた identity も、公開 repo に載る点は同じ。
    ++ forbidUser "a git identity in this repository (local.profile.gitUsername / gitUserEmail / programs.git.settings.user)" (
      u: (u.programs.git.settings.user or { }) != { }
    );
  };
}
