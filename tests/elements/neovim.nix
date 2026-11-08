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
}
