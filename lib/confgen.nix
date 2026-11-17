{
  pkgs,
  configDir ? ../config,
}:
let
  package = pkgs.buildGoModule {
    pname = "confgen";
    version = "0.5.0";
    src = ../tools/confgen;
    vendorHash = "sha256-W6XlFDDA3ynfrM39PaZjoBwGrHaRM8pr7R5I0PkIDCo=";
  };
  generate =
    host: system:
    pkgs.runCommand "confgen-${host}.nix" { nativeBuildInputs = [ package ]; } ''
      confgen build ${configDir} ${pkgs.lib.escapeShellArg host} ${pkgs.lib.escapeShellArg system} "$out"
    '';
in
{
  inherit package generate;
}
