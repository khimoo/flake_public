# confgen（tools/confgen）を build し、config/ の Starlark の要素からホストごとの JSON を作る。
# 評価の途中でこの JSON を読む（IFD）。設計: docs/architecture/confgen.md
{ pkgs }:
let
  inherit (pkgs) lib;
  package = pkgs.buildGoModule {
    pname = "confgen";
    version = "0.1.0";
    src = ../tools/confgen;
    vendorHash = "sha256-AqNYeem4YcsS0EMsn85r3SGknzf66t39hsV69KMTOWA=";
  };
  output = pkgs.runCommand "confgen-output" { nativeBuildInputs = [ package ]; } ''
    confgen build ${../config} $out
  '';
in
{
  inherit package output;
  read = host: lib.importJSON "${output}/${host}.json";
}
