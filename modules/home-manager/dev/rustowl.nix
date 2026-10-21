# RustOwl and its matching Neovim plugin come from the same locked flake.
{ config, inputs, pkgs, lib, ... }:
let
  supported = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
  enabled = config.local.rustowl.enable && supported;
  packages = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};
in {
  options.local.rustowl.enable = lib.mkOption {
    type = lib.types.bool;
    default = supported;
    description = "Install RustOwl from nix-community/rustowl-flake (enabled on x86_64-linux).";
  };

  config = lib.mkMerge [
    {
      assertions = [{
        assertion = !config.local.rustowl.enable || supported;
        message = "local.rustowl currently supports x86_64-linux only.";
      }];
      # Absolute store paths prevent the old ~/.local/bin/rustowl from shadowing
      # the managed server.
      local.neovim.features.rustowl = {
        enable = enabled;
        data = lib.mkIf enabled {
          command = "${packages.rustowl}/bin/rustowl";
          plugin = "${packages.rustowl-nvim}";
        };
      };
    }
    (lib.mkIf enabled {
      home.packages = [ packages.rustowl ];
    })
  ];
}
