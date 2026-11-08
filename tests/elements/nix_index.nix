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
  # 非対話の bash（エージェントのシェル）が、見つからないコマンドに入手方法を添え、127 のまま終わる。
  # 実際の nix-locate と同梱の DB を使う。ビルド環境に node が無いことを前提にする。
  command-not-found-hint =
    (lib.lazyDerivation {
      derivation = (
        if system != "x86_64-linux" then
          pkgs.runCommand "command-not-found-hint-skipped" { } "touch $out"
        else
          pkgs.runCommand "command-not-found-hint" { hint = home.config.home.sessionVariables.BASH_ENV; } ''
            status=0
            BASH_ENV=$hint ${pkgs.bash}/bin/bash -euo pipefail -c 'node --version' 2> err || status=$?
            cat err
            [ "$status" = 127 ]
            grep -q 'nix shell nixpkgs#nodejs' err
            # This pinned small database has exactly one executable candidate for figlet.
            candidates=$(${home.config.programs.nix-index.package}/bin/nix-locate \
              --minimal --no-group --type x --type s --whole-name --at-root /bin/figlet)
            [ "$candidates" = figlet.out ]
            status=0
            BASH_ENV=$hint ${pkgs.bash}/bin/bash -euo pipefail -c 'figlet --version' 2> err || status=$?
            cat err
            [ "$status" = 127 ]
            grep -q 'nix shell nixpkgs#figlet' err
            touch "$out"
          ''
      );
    })
    // {
      elements = [ "nix_index" ];
    };
}
