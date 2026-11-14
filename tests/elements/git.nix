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
        # git_identity を選んだ利用者にだけ、持ち主の名前が入る。
        assert users.alice.programs.git.settings.user.name == "Alice";
        assert !(users.bob.programs.git.settings ? user);
        pkgs.runCommand "git-contracts" { } ''
          echo "git contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "git"
        "git_identity"
      ];
    };
}
