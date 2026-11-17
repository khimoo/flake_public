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
              XSAVED_SERVER = "desktop-ts";
              XSAVED_SERVER_PORT = "8765";
              XSAVED_LOCAL_PORT = "18765";
            }
            && !((purposeHome system "test-xsaved-client").config.systemd.user.services ? xsaved-sync)
          );
        pkgs.runCommand "xsaved-contracts" { } ''
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
        "xsaved_data"
      ];
    };
}
