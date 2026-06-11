{ kiro, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    vscode
    jetbrains.idea
    claude-code
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    kiro.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
