{ pkgs, ... }:

{
  imports = [
    ./lsp.nix
    ./neovim
    ./rustowl.nix
    ./apps.nix
  ];

  home.packages = with pkgs; [
    tree
    ffmpeg
  ];
}
