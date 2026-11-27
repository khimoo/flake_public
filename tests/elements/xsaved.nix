{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers)
    xsavedHost
    nixosHost
    systemAssertionsHold
    rejectsPurpose
    ;
  socketHost = nixosHost "test-xsaved-socket";
  client = nixosHost "test-xsaved-client";
in
{
  xsaved-contracts =
    (lib.lazyDerivation {
      derivation = (
        # マウントのないホストでも使える。GPU は共有のロックファイルで順番にする。
        assert systemAssertionsHold xsavedHost;
        assert systemAssertionsHold socketHost;
        assert xsavedHost.services.postgresql.ensureDatabases == [ "xsaved_alice" ];
        assert socketHost.services.postgresql.ensureDatabases == [ "xsaved_bob" ];
        # xsaved_web_resident を選んだ alice は Web サーバーを常駐させ（GPU ロックと sops 秘密なし）、
        # xsaved_web_socket と xsaved_backup を選んだ bob はソケットから都度起動してバックアップも動かす。
        assert
          xsavedHost.home-manager.users.alice.systemd.user.services.xsaved-web-server.Install.WantedBy
          == [ "default.target" ];
        assert
          xsavedHost.home-manager.users.alice.systemd.user.services.xsaved-web-server.Service.Environment
          == [ "XSAVED_NO_GPU_LOCK=1" ];
        assert lib.hasInfix "--preload" (
          builtins.concatStringsSep " "
            xsavedHost.home-manager.users.alice.systemd.user.services.xsaved-web-server.Service.ExecStart
        );
        assert !(xsavedHost.home-manager.users.alice.systemd.user.sockets ? xsaved-web);
        assert !(xsavedHost.home-manager.users.alice.systemd.user.timers ? xsaved-backup);
        assert
          socketHost.home-manager.users.bob.systemd.user.sockets.xsaved-web.Install.WantedBy
          == [ "sockets.target" ];
        assert !(socketHost.home-manager.users.bob.systemd.user.services.xsaved-web-server ? Install);
        assert socketHost.home-manager.users.bob.systemd.user.timers ? xsaved-backup;
        assert builtins.elem "f /run/xsaved-gpu.lock 0644 root root -" xsavedHost.systemd.tmpfiles.rules;
        # 門番は、そのユーザーの web_port（ソケットなら起動用のソケット）へ渡し、use_xsaved を選んだホストだけを通す。
        assert lib.hasInfix "reverse_proxy 127.0.0.1:8765\n"
          xsavedHost.services.caddy.virtualHosts."http://xsaved.home.arpa:8780".extraConfig;
        assert lib.hasInfix "reverse_proxy 127.0.0.1:8775\n"
          socketHost.services.caddy.virtualHosts."http://xsaved.home.arpa:8780".extraConfig;
        assert lib.hasInfix "test-xsaved-client"
          xsavedHost.services.caddy.virtualHosts."http://xsaved.home.arpa:8780".extraConfig;
        # Web UI の名前は tailnet に 1 つなので、1 台で xsaved を動かすのは 1 人まで。
        assert rejectsPurpose "test-xsaved-two-users" "x86_64-linux" "only one user per host can select serve_xsaved";
        # データベースは NixOS 側が作るので、NixOS の設定を作らないホストでは confgen が止める。
        assert rejectsPurpose "test-xsaved-standalone" "x86_64-linux" "needs nixos_system";
        # クライアントは xsaved.home.arpa を自分へ向け、手元の Caddy が自分用サーバ（nixos-gce）の門番へ渡す。
        assert builtins.elem "xsaved.home.arpa" client.networking.hosts."127.0.0.1";
        assert
          client.services.caddy.virtualHosts."http://xsaved.home.arpa".extraConfig
          == "reverse_proxy nixos-gce:8780\n";
        assert !(client.home-manager.users.test.systemd.user.services ? xsaved-sync);
        pkgs.runCommand "xsaved-contracts" { } ''
          ${lib.optionalString (system == "x86_64-linux") ''
            env_bin=${
              lib.findFirst (p: (p.name or "") == "xsaved-env") (throw "xsaved-env is not installed")
                xsavedHost.home-manager.users.alice.home.packages
            }/bin/xsaved-env
            cli_bin=${
              lib.findFirst (p: (p.name or "") == "xsaved") (throw "xsaved is not installed")
                xsavedHost.home-manager.users.alice.home.packages
            }/bin/xsaved
            init=$(sed -n 's/.*--symlink \([^ ]*-xsaved-env-init\) \/init.*/\1/p' "$env_bin")
            run=$(sed -n 's/^exec \([^ ]*-xsaved-env-run\).*/\1/p' "$init")
            grep -qF 'XSAVED_ML_EXTRA=ml-cpu' "$run"
            grep -qF 'XSAVED_ML_EXTRA=ml-cpu' "$cli_bin"
          ''}
          echo "xsaved contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "checkout"
        "failure_notify"
        "machine_base"
        "connect_ssh"
        "find_home_server"
        "serve_xsaved"
        "use_xsaved"
        "tailnet_web"
        "tailnet_gate"
        "xsaved_backup"
        "xsaved_data"
        "xsaved_web_resident"
        "xsaved_web_socket"
      ];
    };
}
