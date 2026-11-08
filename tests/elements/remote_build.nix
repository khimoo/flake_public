{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers)
    home
    laptop
    systemAssertionsHold
    rejectsPurpose
    ;
in
{
  remote_build-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert systemAssertionsHold laptop;
        assert laptop.nix.buildMachines != [ ];
        # nix-daemon は Host ブロックを経由して接続するため、buildMachines と SSH の接続名が一致する必要がある。
        assert builtins.all (
          m: lib.hasInfix "Host ${m.hostName}\n" laptop.programs.ssh.extraConfig
        ) laptop.nix.buildMachines;
        assert builtins.all (m: m.sshKey == "/home/alice/.ssh/id_lan") laptop.nix.buildMachines;
        # builders に自分しかいないホストでは回す先がない。黙って何もしない設定にしない。
        assert rejectsPurpose "test-remote-build-self" "x86_64-linux"
          "remote_build: no other host has a builder";
        pkgs.runCommand "remote_build-contracts" { } ''
          echo "remote_build contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "checkout"
        "machine_base"
        "machine_ssh"
        "machine_ssh_tailnet"
        "remote_build"
        "tailscale"
      ];
    };
}
