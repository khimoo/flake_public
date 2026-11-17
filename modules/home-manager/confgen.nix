{
  host,
  system,
  user,
  configDir ? ../../config,
  generatorPkgs ? null,
}:
{ inputs, ... }:
# 生成器の pkgs を module の設定値から求めると、生成する設定自身への依存が生じ、無限再帰になる。
(import
  (
    (import ../../lib/confgen.nix {
      pkgs = if generatorPkgs == null then inputs.nixpkgs.legacyPackages.${system} else generatorPkgs;
      inherit configDir;
    }).generate
      host
      system
  )
  {
    inherit inputs;
    repoRoot = ../..;
  }
).homes.${user}
