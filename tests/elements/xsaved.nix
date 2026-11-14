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
        # クライアントは、自分用サーバで xsaved を動かす利用者の web_port へ ssh で転送する。
        assert
          system != "x86_64-linux"
          || (
            let
              result =
                (import ../../lib/confgen.nix {
                  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
                  inherit configDir;
                }).read
                  "test-xsaved-client"
                  system
                  "test";
              packages = lib.findFirst (
                s:
                s.path == [
                  "home"
                  "packages"
                ]
              ) null result.elements.use_xsaved.home;
              env = builtins.elemAt (builtins.head packages.value)."$shellAppEnv" 2;
            in
            env == {
              XSAVED_SERVER = "desktop-ts";
              XSAVED_SERVER_PORT = "8765";
              XSAVED_LOCAL_PORT = "18765";
            }
            && !(result.elements ? serve_xsaved)
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
