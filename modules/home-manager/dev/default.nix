{ pkgs, ... }:

{
  imports = [
    ./agent-compression.nix
    ./claude.nix
    ./codex.nix
    ./agent-sync.nix
  ];

  home.packages = with pkgs; [
    tree
    ffmpeg
  ];
}
