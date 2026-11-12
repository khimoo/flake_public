# config/hosts/<host>.toml で利用者ごとに選んだ purposes から confgen が生成した NixOS の設定を入れる。
# どれかの利用者で判定が真の要素のホスト全体の設定と、利用者ごとの NixOS の設定が入る。
# 設計: docs/architecture/confgen.md
{ host, system, configDir ? ../../config }:
{ inputs, pkgs, lib, ... }:
import ../../lib/confgen-bridge.nix {
  inherit lib pkgs inputs;
  class = "nixos";
  result = (import ../../lib/confgen.nix { pkgs = inputs.nixpkgs.legacyPackages.${system}; inherit configDir; }).readHost host system;
}
