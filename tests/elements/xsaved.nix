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
    allAssertions
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
        # データベースは NixOS 側が作るので、Home Manager 単独では有効にできない。
        # Home Manager は失敗した assertion を評価のエラーにすることがあるので、tryEval で受ける。
        assert
          let
            r = builtins.tryEval (allAssertions (purposeHome "x86_64-linux" "test-xsaved-standalone"));
          in
          !r.success || !r.value;
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
        "xsaved"
      ];
    };
}
