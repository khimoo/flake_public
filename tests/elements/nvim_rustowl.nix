{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) home neovimFeatures;
in
{
  nvim_rustowl-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert !(home.config.home.activation ? rustowl);
        assert !(builtins.any (p: (p.pname or "") == "rustowl") home.config.home.packages);
        assert builtins.elem "rustowl" (neovimFeatures system) == (system == "x86_64-linux");
        pkgs.runCommand "nvim_rustowl-contracts" { } ''
          echo "nvim_rustowl contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "nvim_rustowl"
        "neovim"
      ];
    };
}
