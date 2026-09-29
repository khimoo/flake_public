# comma and the nix-index command-not-found handler share the prebuilt small
# database, which indexes bin/ only. Rationale: docs/architecture/comma.md.
{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.nix-index-database.homeModules.nix-index ];

  programs.nix-index-database.comma.enable = lib.mkDefault true;

  programs.nix-index = {
    package = inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system}.nix-index-with-small-db;
    # The upstream module links the full database (about 100 MiB) into
    # ~/.cache/nix-index. Both wrappers set NIX_INDEX_DATABASE and never read it.
    symlinkToCacheHome = lib.mkDefault false;
  };
}
