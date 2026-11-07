# confgen（tools/confgen）を build し、config/ の Starlark の要素から1つのホストの JSON を作る。
# 評価の途中でこの JSON を読む（IFD）。設計: docs/architecture/confgen.md
{ pkgs }:
let
  inherit (pkgs) lib;
  package = pkgs.buildGoModule {
    pname = "confgen";
    version = "0.3.0";
    src = ../tools/confgen;
    vendorHash = "sha256-AqNYeem4YcsS0EMsn85r3SGknzf66t39hsV69KMTOWA=";
  };
in
{
  inherit package;
  read =
    host: system: user:
    lib.importJSON (
      pkgs.runCommand "confgen-${host}-${user}.json" { nativeBuildInputs = [ package ]; } ''
        confgen build ${../config} ${host} ${system} ${user} $out
      ''
    );
}
