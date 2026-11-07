{ pkgs, ... }:

{
  home.packages = with pkgs; [
    tree
    ffmpeg
  ];
}
