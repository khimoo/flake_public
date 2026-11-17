{
  host,
  system,
  configDir ? ../../config,
}:
{ inputs, ... }:
(import
  (
    (import ../../lib/confgen.nix {
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      inherit configDir;
    }).generate
      host
      system
  )
  {
    inherit inputs;
    repoRoot = ../..;
  }
).nixos
