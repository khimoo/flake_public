# config/hosts/<host>.toml で選んだ目的から confgen が生成した NixOS の設定を入れる。
# 目的はホストごとに選ぶので、primaryUser で評価した結果の nixos の部分を使う。
# 設計: docs/architecture/confgen.md
{ host, system, user, configDir ? ../../config }:
{ inputs, pkgs, lib, ... }:
import ../../lib/confgen-bridge.nix {
  inherit lib pkgs inputs;
  class = "nixos";
  result = (import ../../lib/confgen.nix { pkgs = inputs.nixpkgs.legacyPackages.${system}; inherit configDir; }).read host system user;
}
