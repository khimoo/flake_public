{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) users;
in
{
  git-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert users.alice.programs.git.settings.user.name == "Alice";
        assert !(users.bob.programs.git.settings ? user);
        pkgs.runCommand "git-contracts" { } ''
          echo "git contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [ "git" ];
    };
}
