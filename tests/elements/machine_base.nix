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
    ;
in
{
  machine_base-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert !(users ? unmanaged);
        pkgs.runCommand "machine_base-contracts" { } ''
          echo "machine_base contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "checkout"
        "machine_base"
      ];
    };
}
