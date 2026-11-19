{ config, lib, modulesPath, pkgs, ... }:
let
  publisher = pkgs.writeShellApplication {
    name = "flake-publish-cache";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.google-cloud-sdk
      pkgs.jq
      pkgs.sops
      config.nix.package
    ];
    inheritPath = false;
    text = builtins.readFile ../../scripts/ci/publish-cache.sh;
  };
in
{
  imports = [ (modulesPath + "/virtualisation/google-compute-image.nix") ];

  networking.hostName = "flake-cache-worker";
  networking.useDHCP = true;
  networking.firewall.enable = true;
  networking.nftables.enable = true;
  networking.nftables.tables.metadata-root-only = {
    family = "ip";
    content = ''
      chain output {
        type filter hook output priority filter; policy accept;
        ip daddr 169.254.169.254 tcp dport 80 meta skuid != 0 reject
      }
    '';
  };
  virtualisation.googleComputeImage.efi = true;
  virtualisation.googleComputeImage.compressionLevel = 1;
  system.stateVersion = "26.05";
  users.mutableUsers = false;
  # Headless, managed by the deployment image; no interactive accounts or SSH.
  users.allowNoPasswordLogin = true;
  services.openssh.enable = lib.mkForce false;
  security.googleOsLogin.enable = lib.mkForce false;
  systemd.services.google-startup-scripts.enable = false;
  systemd.services.google-shutdown-scripts.enable = false;

  users.groups.flake-build = { };
  users.users.flake-build = {
    isSystemUser = true;
    group = "flake-build";
    home = "/var/lib/flake-build";
    createHome = true;
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    sandbox = true;
    max-jobs = 2;
    cores = 2;
    substituters = lib.mkAfter [ "https://cache.numtide.com" ];
    trusted-public-keys = lib.mkAfter [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  systemd.services.flake-cache-worker = {
    description = "Build and publish an immutable NixOS cache release";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "nix-daemon.socket" ];
    path = with pkgs; [ age bash coreutils curl git google-cloud-sdk jq util-linux config.nix.package ];
    environment = {
      PUBLISH_CACHE = lib.getExe publisher;
      NIX_REMOTE = "daemon";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${../../scripts/ci/cache-worker.sh}";
      StateDirectory = "flake-cache-worker";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "flake-cache-worker";
      RuntimeDirectoryMode = "0700";
      TimeoutStartSec = "5h";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };
}
