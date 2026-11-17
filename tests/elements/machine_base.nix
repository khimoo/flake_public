{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers)
    users
    inputs
    home
    ;
  policyFromElement =
    name:
    let
      definitions =
        inputs.self.nixosConfigurations.nixos-desktop.options.home-manager.${name}.definitionsWithLocations;
    in
    definitions != [ ]
    && builtins.all (definition: definition.file == "config/elements/machine_base.star") definitions;

in
{
  machine_base-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert !(users ? unmanaged);
        assert home.config.nixpkgs.config.allowUnfree;
        assert policyFromElement "backupFileExtension";
        assert policyFromElement "useGlobalPkgs";
        assert policyFromElement "useUserPackages";
        pkgs.runCommand "machine_base-contracts" { } ''
          echo "machine_base contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "checkout"
        "machine_base"
        "home_base"
      ];
    };
}
