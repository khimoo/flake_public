# confgen（tools/confgen）を build し、config/ の Starlark の要素から1つのホストの JSON を作る。
# JSON は、ホスト全体の NixOS の設定（elements）と、利用者ごとの設定（users.<利用者>.elements）を持つ。
# 評価の途中でこの JSON を読む（IFD）。設計: docs/architecture/confgen.md
# configDir は既定で config/。テストは架空のホスト（tests/hosts）を足したディレクトリを渡す。
{ pkgs, configDir ? ../config }:
let
  inherit (pkgs) lib;
  package = pkgs.buildGoModule {
    pname = "confgen";
    version = "0.4.0";
    src = ../tools/confgen;
    vendorHash = "sha256-W6XlFDDA3ynfrM39PaZjoBwGrHaRM8pr7R5I0PkIDCo=";
  };
  readHost =
    host: system:
    lib.importJSON (
      pkgs.runCommand "confgen-${host}.json" { nativeBuildInputs = [ package ]; } ''
        confgen build ${configDir} ${host} ${system} $out
      ''
    );
in
{
  inherit package readHost;
  read = host: system: user: (readHost host system).users.${user};
}
