# どのホストでも要る設定だけを置く。desktop 向けの機能は common.nix が足すので、ここには入れない
# （docs/architecture/wsl.md）。
{ config, lib, specialArgs, ... }:
let
  primaryHome = config.home-manager.users.${specialArgs.settings.primaryUser} or null;
in
{
  imports = [
    ./locale.nix
    ./users.nix
    ./nix-settings.nix
    ./codex.nix
    ./agent-instructions.nix
    ./claude-managed-settings.nix
    ./restricted-host.nix
  ];

  networking.hostName = specialArgs.settings.hostname;
  system.stateVersion = specialArgs.settings.stateVersion;

  # `--flake` なしの nixos-rebuild が読む /etc/nixos/flake.nix を、checkout から見つけられるようにする。
  # flake.nix だけでなくディレクトリごとリンクにし、L+ で既存の /etc/nixos を中身ごと置き換える
  # （理由は docs/architecture/configuration.md）。
  systemd.tmpfiles.rules = lib.optional (primaryHome != null) "L+ /etc/nixos - - - - ${primaryHome.local.profile.flakeRoot}";
}
