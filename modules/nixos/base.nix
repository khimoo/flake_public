# どのホストでも要る設定だけを置く。desktop 向けの機能は common.nix が足すので、ここには入れない
# （docs/architecture/wsl.md）。
{ specialArgs, ... }: {
  imports = [
    ./locale.nix
    ./users.nix
    ./nix-settings.nix
    ./codex.nix
    ./agent-instructions.nix
    ./claude-managed-settings.nix
    ./permit-insecure.nix
  ];

  networking.hostName = specialArgs.settings.hostname;
  system.stateVersion = specialArgs.settings.stateVersion;
}
