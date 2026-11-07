# confgen の JSON を NixOS / Home Manager のモジュールにする共通の処理。
# class は "home" か "nixos"。special は class にしかない印の置き換え（例: activation）を返す関数で、
# 中の値を置き換える resolve を受け取る。
{
  lib,
  pkgs,
  inputs,
  result,
  class,
  special ? (_: { }),
}:
let
  pkgByName = name: lib.getAttrFromPath (lib.splitString "." name) pkgs;

  common = {
    "$pkg" = v: pkgByName v;
    "$exe" = v: lib.getExe' (pkgByName (builtins.elemAt v 0)) (builtins.elemAt v 1);
    "$concat" = v: lib.concatMapStrings resolve v;
    "$luaPackages" = v: ps: map (name: ps.${name}) v;
    "$lua" = v: lib.generators.toLua { } (resolve v);
    "$script" = v: pkgs.writeShellScript (builtins.elemAt v 0) (resolve (builtins.elemAt v 1));
    "$scriptBin" = v: pkgs.writeShellScriptBin (builtins.elemAt v 0) (resolve (builtins.elemAt v 1));
    "$file" = v: pkgs.writeText (builtins.elemAt v 0) (resolve (builtins.elemAt v 1));
    "$shellApp" =
      v:
      pkgs.writeShellApplication {
        name = builtins.elemAt v 0;
        runtimeInputs = resolve (builtins.elemAt v 1);
        text = resolve (builtins.elemAt v 2);
      };
    "$repoPkg" = v: pkgs.callPackage (../. + "/${builtins.head v}") { };
    "$symlinkJoin" =
      v:
      pkgs.symlinkJoin {
        name = builtins.elemAt v 0;
        paths = resolve (builtins.elemAt v 1);
      };
    "$command" = v: pkgs.runCommand (builtins.elemAt v 0) { } (resolve (builtins.elemAt v 1));
    "$inputPkg" = v: inputs.${builtins.elemAt v 0}.packages.${pkgs.stdenv.hostPlatform.system}.${builtins.elemAt v 1};
  };
  handlers = common // special resolve;

  # 印は "$" で始まるキーを1つだけ持つ attrset。
  markerKey =
    v:
    let
      keys = builtins.attrNames v;
    in
    if builtins.length keys == 1 && lib.hasPrefix "$" (builtins.head keys) then builtins.head keys else null;

  resolve =
    v:
    if builtins.isAttrs v then
      let
        k = markerKey v;
      in
      if k == null then
        lib.mapAttrs (_: resolve) v
      else if handlers ? ${k} then
        handlers.${k} v.${k}
      else
        throw "confgen: the ${k} marker cannot be used in ${class} settings"
    else if builtins.isList v then
      map resolve v
    else
      v;

  importOf =
    m:
    if m ? "$module" then
      lib.getAttrFromPath (lib.splitString "." (builtins.elemAt m."$module" 1)) inputs.${builtins.elemAt m."$module" 0}
    else
      ../. + "/${m."$repoModule"}";

  # 要素ごとに別のモジュールにし、型の誤りなどのエラーに要素のファイル名が出るようにする。
  moduleOf = name: element: {
    _file = "config/elements/${name}.star";
    imports = map importOf (element."${class}_imports" or [ ]);
    config = lib.mkMerge (
      map (setting: lib.setAttrByPath setting.path (resolve setting.value)) (element.${class} or [ ])
    );
  };
in
{
  imports = lib.mapAttrsToList moduleOf result.elements;
}
