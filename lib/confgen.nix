# confgen（tools/confgen）を build し、config/ の Starlark の要素から1つのホストの JSON を作る。
# 評価の途中でこの JSON を読む（IFD）。設計: docs/architecture/confgen.md
# configDir は既定で config/。テストは架空のホスト（tests/hosts）を足したディレクトリを渡す。
{ pkgs, configDir ? ../config }:
let
  inherit (pkgs) lib;
  package = pkgs.buildGoModule {
    pname = "confgen";
    version = "0.3.0";
    src = ../tools/confgen;
    vendorHash = "sha256-W6XlFDDA3ynfrM39PaZjoBwGrHaRM8pr7R5I0PkIDCo=";
  };
in
{
  inherit package;
  read =
    host: system: user:
    lib.importJSON (
      pkgs.runCommand "confgen-${host}-${user}.json" { nativeBuildInputs = [ package ]; } ''
        confgen build ${configDir} ${host} ${system} ${user} $out
      ''
    );
}
