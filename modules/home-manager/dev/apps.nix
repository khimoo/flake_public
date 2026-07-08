{ inputs, kiro, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    vscode
    jetbrains.idea
    claude-code
    inputs.claude-history.packages.${pkgs.stdenv.hostPlatform.system}.default
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    kiro.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
