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
        # 自分用サーバで作った成果物には署名がないので、取り込む利用者を信頼する。
        assert builtins.elem "alice" laptop.nix.settings.trusted-users;
        # 自分自身を任せる先にしたホストは、回す先がない。黙って何もしない設定にしない。
        assert rejectsPurpose "test-remote-build-self" "x86_64-linux"
          "remote_build: build_host is this host";
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
        "lan_ssh_key"
        "remote_build"
        "tailscale"
      ];
    };
}
