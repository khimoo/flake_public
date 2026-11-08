{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) home users rejectsPurpose;
in
{
  secrets-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert !(lib.hasInfix "id_lan" users.bob.home.activation.secrets.data);
        assert !(lib.hasInfix "id_github" users.bob.home.activation.secrets.data);
        assert lib.hasInfix "/home/alice/.ssh/id_github" users.alice.home.activation.secrets.data;
        assert lib.hasInfix "/home/alice/.ssh/id_lan" users.alice.home.activation.secrets.data;
        assert users.bob.home.activation ? secrets;
        assert !(lib.hasInfix "SOPS_AGE_KEY_FILE" users.bob.home.activation.secrets.data);
        assert !(lib.hasInfix "age_key=" users.bob.home.activation.secrets.data);
        assert users.alice.home.activation ? secrets;
        # 暗号文が世代の closure に入る（GC 後の起動時の activation でも復号できる）。
        assert lib.any (lib.hasSuffix "-secrets.yaml") (
          lib.attrNames (builtins.getContext users.alice.home.activation.secrets.data)
        );
        assert rejectsPurpose "test-duplicate-secret" "x86_64-linux"
          "personal_files: duplicate secret destination";
        assert rejectsPurpose "test-outside-secret" "x86_64-linux"
          "personal_files: destinations must live below";
        assert rejectsPurpose "test-ssh-duplicate" "x86_64-linux"
          "personal_files: duplicate SSH key filename";
        assert rejectsPurpose "test-ssh-collision" "x86_64-linux" "secrets: duplicate SSH key filename";
        pkgs.runCommand "secrets-contracts" { } ''
          echo "secrets contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "secrets"
        "personal_files"
      ];
    };
}
