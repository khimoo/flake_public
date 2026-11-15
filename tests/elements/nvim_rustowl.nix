{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) home neovimFeatures rejectsPurpose;
in
{
  nvim_rustowl-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert !(home.config.home.activation ? rustowl);
        assert !(builtins.any (p: (p.pname or "") == "rustowl") home.config.home.packages);
        # x86_64 の Linux でないホストで daily_editing を選ぶと、黙って RustOwl を外さずに止まる。
        assert
          if system == "x86_64-linux" then
            builtins.elem "rustowl" (neovimFeatures system)
          else
            rejectsPurpose "test-neovim-features" system "needs x86_64_linux";
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
