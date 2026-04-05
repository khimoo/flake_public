# Claude Desktop (FHS版) パッケージ + Wayland IME 対応
{ claude-desktop-debian, pkgs, ... }:

let
  claude-desktop-pkg = claude-desktop-debian.packages.${pkgs.system}.claude-desktop-fhs;

  # Wayland IME フラグを付与したラッパー
  claude-desktop-wrapped = pkgs.symlinkJoin {
    name = "claude-desktop-wrapped";
    paths = [ claude-desktop-pkg ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude-desktop \
        --add-flags "--ozone-platform-hint=auto --enable-wayland-ime --wayland-text-input-version=3"
    '';
  };

in {
  home.packages = [ claude-desktop-wrapped ];
}
