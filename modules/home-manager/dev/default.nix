{ pkgs, ... }:

{
  imports = [
    ./lsp.nix
    ./neovim
    ./rustowl.nix
    ./cargo-remote-run.nix
    ./agent-compression.nix
    ./apps.nix
    ./claude.nix
    ./codex.nix
  ];

  home.packages = with pkgs; [
    tree
    ffmpeg
  ];
}
