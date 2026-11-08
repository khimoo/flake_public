{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) home allAssertions;
in
{
  dev_tools-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert allAssertions home;
        assert !(builtins.any (p: (p.pname or "") == "vscode") home.config.home.packages);
        pkgs.runCommand "dev_tools-contracts" { } ''
          echo "dev_tools contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "checkout"
        "dev_tools"
        "git"
        "nix_index"
        "private_repos"
        "secrets"
        "shell"
        "yazi"
      ];
    };
}
