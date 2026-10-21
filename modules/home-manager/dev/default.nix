{ pkgs, ... }:

{
  imports = [
    ./neovim
    ./uv-mode.nix
    ./rustowl.nix
    ./cargo-remote-run.nix
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
