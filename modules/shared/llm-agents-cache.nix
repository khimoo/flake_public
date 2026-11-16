{ inputs, lib, pkgs, ... }:
let
  # nixConfig は flake の出力に含まれないため、固定したソースから読む。
  cache = (import (inputs.llm-agents + "/flake.nix")).nixConfig;
in
{
  # Home Manager は nix.conf の生成に nix.package を要求する。
  nix.package = lib.mkDefault pkgs.nix;
  nix.settings = {
    inherit (cache) extra-substituters extra-trusted-public-keys;
  };
}
