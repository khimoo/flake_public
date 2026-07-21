{ pkgs, ... }:

{
  imports = [
    ./lsp.nix
    ./neovim
    ./rustowl.nix
    ./apps.nix
    ./claude.nix
  ];

  home.packages = with pkgs; [
    tree
    ffmpeg
  ];
}
