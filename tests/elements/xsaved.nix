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
    systemAssertionsHold
    purposeHome
    rejectsPurpose
    inputs
    configDir
    generatedEnvironment
    ;
in
{
  xsaved-contracts =
    (lib.lazyDerivation {
      derivation = (
        # 複数のユーザーとマウントのないホストでも使える。GPU は共有のロックファイルで順番にする。
        assert systemAssertionsHold xsavedHost;
        assert
          xsavedHost.services.postgresql.ensureDatabases == [
            "xsaved_alice"
            "xsaved_bob"
          ];
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
          xsavedHost.home-manager.users.bob.systemd.user.sockets.xsaved-web.Install.WantedBy
          == [ "sockets.target" ];
        assert !(xsavedHost.home-manager.users.bob.systemd.user.services.xsaved-web-server ? Install);
        assert xsavedHost.home-manager.users.bob.systemd.user.timers ? xsaved-backup;
        assert builtins.elem "f /run/xsaved-gpu.lock 0644 root root -" xsavedHost.systemd.tmpfiles.rules;
        # データベースは NixOS 側が作るので、NixOS の設定を作らないホストでは confgen が止める。
        assert rejectsPurpose "test-xsaved-standalone" "x86_64-linux" "needs nixos_system";
        # クライアントは、自分用サーバで xsaved を動かすユーザーの web_port へ ssh で転送する。
        assert
          system != "x86_64-linux"
          || (
            let
              env = generatedEnvironment "test-xsaved-client" system "use_xsaved";
            in
            env == {
              XSAVED_SERVER = "gce-ts";
              XSAVED_SERVER_PORT = "8765";
              XSAVED_LOCAL_PORT = "18765";
            }
            && !((purposeHome system "test-xsaved-client").config.systemd.user.services ? xsaved-sync)
          );
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
        "xsaved_backup"
        "xsaved_data"
        "xsaved_web_resident"
        "xsaved_web_socket"
      ];
    };
}
