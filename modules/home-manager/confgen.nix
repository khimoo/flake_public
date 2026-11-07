# config/hosts/<host>.star で選んだ目的から confgen が生成した Home Manager の設定を入れる。
# 設計: docs/architecture/confgen.md
#
# host と system は import するときに渡す。config.* や pkgs から決めると、設定の名前の一覧を
# 決めるのに設定そのものが要り、無限再帰になる。confgen の build には specialArgs の inputs を使う。
{ host, system }:
{ inputs, pkgs, lib, ... }:
let
  confgen = import ../../lib/confgen.nix { pkgs = inputs.nixpkgs.legacyPackages.${system}; };
  result = confgen.read host;

  # confgen の印（pkg / exe / concat）を、このホストの pkgs の値に置き換える。
  resolve =
    v:
    if builtins.isAttrs v then
      if v ? "$pkg" then
        pkgs.${v."$pkg"}
      else if v ? "$exe" then
        lib.getExe' pkgs.${builtins.elemAt v."$exe" 0} (builtins.elemAt v."$exe" 1)
      else if v ? "$concat" then
        lib.concatMapStrings (part: resolve part) v."$concat"
      else
        lib.mapAttrs (_: resolve) v
    else if builtins.isList v then
      map resolve v
    else
      v;

  # 要素ごとに別のモジュールにし、型の誤りなどのエラーに要素のファイル名が出るようにする。
  moduleOf =
    name: element:
    assert lib.assertMsg (!(element ? nixos)) "confgen: ${name} sets NixOS options, which this bridge does not apply yet";
    {
      _file = "config/elements/${name}.star";
      config = lib.mkMerge (
        lib.mapAttrsToList (path: value: lib.setAttrByPath (lib.splitString "." path) (resolve value)) (
          element.home or { }
        )
      );
    };
in
{
  imports = lib.mapAttrsToList moduleOf result.elements;
}
