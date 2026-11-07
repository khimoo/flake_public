# config/hosts/<host>.toml で選んだ目的から confgen が生成した Home Manager の設定を入れる。
# 設計: docs/architecture/confgen.md
#
# host、system、user は import するときに渡す。config.* や pkgs から決めると、設定の名前の一覧を
# 決めるのに設定そのものが要り、無限再帰になる。confgen の build には specialArgs の inputs を使う。
{ host, system, user }:
{ inputs, config, pkgs, lib, ... }:
import ../../lib/confgen-bridge.nix {
  inherit lib pkgs inputs;
  class = "home";
  result = (import ../../lib/confgen.nix { pkgs = inputs.nixpkgs.legacyPackages.${system}; }).read host system user;
  special = resolve: {
    "$outOfStoreLink" = v: config.lib.file.mkOutOfStoreSymlink (builtins.head v);
    "$checkoutLink" = rel: config.lib.file.mkOutOfStoreSymlink "${config.local.profile.flakeRoot}/${rel}";
    "$activation" = v: lib.hm.dag.entryAfter (builtins.elemAt v 0) (resolve (builtins.elemAt v 1));
    "$gvariantTuple" = v: lib.hm.gvariant.mkTuple (builtins.head v);
  };
}
