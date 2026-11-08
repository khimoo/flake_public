{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers)
    users
    nixosHost
    systemAssertionsHold
    rejectsPurpose
    ;
in
{
  machine_base-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert systemAssertionsHold (nixosHost "test-restricted-ok");
        assert builtins.all
          (name: rejectsPurpose "test-restricted-${name}" "x86_64-linux" "restricted host:")
          [
            "machine-ssh"
            "tailscale"
            "remote-build"
            "lan"
            "git"
            "clone"
            "secrets"
          ];
        assert !(users ? unmanaged);
        pkgs.runCommand "machine_base-contracts" { } ''
          echo "machine_base contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "checkout"
        "machine_base"
        "secrets"
        "machine_ssh"
        "tailscale"
        "remote_build"
        "personal_files"
        "git"
        "private_repos"
      ];
    };
}
