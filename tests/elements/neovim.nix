{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) home;
in
{
  neovim-contracts =
    (lib.lazyDerivation {
      derivation = (
        # ~/.config/nvim は checkout への live symlink なので、その下に置くファイルは home-manager-files の
        # ビルドで "outside $HOME" になる。評価だけでは見つからないので、ここで止める。
        assert
          !(builtins.any (f: f.enable && lib.hasPrefix ".config/nvim/" f.target) (
            builtins.attrValues home.config.home.file
          ));
        pkgs.runCommand "neovim-contracts" { } ''
          echo "neovim contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [ "neovim" ];
    };

  smart-splits-kitty =
    (lib.lazyDerivation {
      derivation =
        let
          configuredPkgs = import helpers.inputs.nixpkgs {
            inherit system;
            inherit (helpers.configurations) overlays;
          };
          # レイアウト問い合わせだけを代替し、PTY と Neovim は実物を使う。
          kittyStub = pkgs.writeShellScriptBin "kitty" ''
            test "$*" = '@ ls' || exit 1
            printf '[]\n'
          '';
        in
        pkgs.runCommand "smart-splits-kitty"
          {
            nativeBuildInputs = [
              pkgs.neovim
              pkgs.python3
              kittyStub
            ];
          }
          ''
            python3 ${../smart-splits-kitty.py} ${configuredPkgs.vimPlugins.smart-splits-nvim}
            touch "$out"
          '';
    })
    // {
      elements = [
        "nvim_smart_splits"
        "kitty"
      ];
    };
}
