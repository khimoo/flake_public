{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers)
    inputs
    configDir
    home
    purposeHome
    rejectsPurpose
    allAssertions
    ;
in
{
  quaderno-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert !(home.config.systemd.user.timers ? quaderno-archive);
        assert
          system != "x86_64-linux"
          || (
            let
              units = (purposeHome system "test-quaderno").config.systemd.user;
            in
            units.timers ? quaderno-archive
            && units.timers ? quaderno-send
            # Send が空の間は、毎分の実行が Quaderno を探さない。
            && units.services.quaderno-send.Unit.ConditionDirectoryNotEmpty == "/home/test/Quaderno/Send"
          );
        assert
          system != "x86_64-linux"
          || (
            let
              result =
                (import ../../lib/confgen.nix {
                  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
                  inherit configDir;
                }).read
                  "test-quaderno"
                  system
                  "test";
              packages = lib.findFirst (
                s:
                s.path == [
                  "home"
                  "packages"
                ]
              ) null result.elements.quaderno.home;
            in
            let
              env = builtins.elemAt (builtins.head packages.value)."$shellAppEnv" 2;
            in
            # 取り込みは自分用サーバへ ssh で送る。手元にアーカイブと記録を持たない。
            env.QUADERNO_SERIAL == ""
            && env.QUADERNO_ARCHIVE_SSH == "desktop-ts"
            && !(env ? QUADERNO_ARCHIVE_DIR)
            && !(env ? QUADERNO_STATE_FILE)
            && env.QUADERNO_EXCHANGE_REMOTE == "Document/PC-Exchange"
            # 手元への受け取りは、自分用サーバを使わずに利用者のキャッシュへ落とす。
            && env.QUADERNO_RECEIVE_DIR == "/home/test/.cache/quaderno/Received"
            && env.QUADERNO_RECEIVE_STATE == "/home/test/.cache/quaderno/received.json"
          );
        # 自分用サーバへ接続できないホストは、受け渡しだけをして、取り込みの設定を持たない。
        assert
          system != "x86_64-linux"
          || (
            let
              result =
                (import ../../lib/confgen.nix {
                  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
                  inherit configDir;
                }).read
                  "test-quaderno-exchange"
                  system
                  "test";
              packages = lib.findFirst (
                s:
                s.path == [
                  "home"
                  "packages"
                ]
              ) null result.elements.quaderno.home;
              env = builtins.elemAt (builtins.head packages.value)."$shellAppEnv" 2;
            in
            !(env ? QUADERNO_ARCHIVE_DIR)
            && !(env ? QUADERNO_ARCHIVE_SSH)
            # 取り込みの設定が無ければ、取り込みの timer も持たない。
            && !((purposeHome system "test-quaderno-exchange").config.systemd.user.timers ? quaderno-archive)
            && env.QUADERNO_SEND_DIR == "/home/test/Quaderno/Send"
          );
        assert rejectsPurpose "test-quaderno-other-home" "x86_64-linux"
          "quaderno: archive points to another user's home";
        # home の外は許す。別ディスクへ置く構成を弾かないこと。
        assert system != "x86_64-linux" || allAssertions (purposeHome system "test-quaderno-backup");
        assert rejectsPurpose "test-quaderno-missing-archive" "x86_64-linux" "quaderno_archive";
        pkgs.runCommand "quaderno-contracts" { } ''
          echo "quaderno contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "failure_notify"
        "connect_ssh"
        "find_home_server"
        "ssh_server"
        "quaderno"
        "use_quaderno_archive"
        "quaderno_exchange"
        "serve_quaderno_archive"
      ];
    };

  quaderno-plan =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "quaderno-plan" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          cp ${../../modules/home-manager/quaderno_plan.py} quaderno_plan.py
          cp ${../../modules/home-manager/quaderno_archive.py} quaderno_archive.py
          cp ${../quaderno-plan.py} test_quaderno_plan.py
          cp ${../quaderno-archive.py} test_quaderno_archive.py
          python test_quaderno_plan.py
          python test_quaderno_archive.py
          touch "$out"
        ''
      );
    })
    // {
      elements = [ "quaderno" ];
    };
}
