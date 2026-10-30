{ pkgs, ... }:

{
  imports = [
    ./neovim
    ./cargo-remote-run.nix
    ./alook-open.nix
    ./agent-compression.nix
    ./apps.nix
    ./claude.nix
    ./codex.nix
    ./agent-sync.nix
  ];

  home.packages = with pkgs; [
    tree
    ffmpeg
  ];
}
