{ pkgs, ... }:

{
  imports = [
    ./lsp.nix
    ./neovim
    ./rustowl.nix
    ./apps.nix
    ./claude.nix
    ./codex.nix
  ];

  home.packages = with pkgs; [
    tree
    ffmpeg
  ];
}
