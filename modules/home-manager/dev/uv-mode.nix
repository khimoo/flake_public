{ lib, pkgs, ... }:

# buildFHSEnv は Linux でしか作れない（docs/architecture/uv-mode.md）。
lib.mkIf pkgs.stdenv.isLinux {
  home.packages = [ (pkgs.callPackage ../../../packages/uv-mode { }) ];

  # モードの外では uv が取得した Python を起動できないため、目印を表示する。
  programs.starship.settings.env_var.IN_UV_MODE = {
    format = "[uv-mode]($style) ";
    style = "bold yellow";
  };
}
