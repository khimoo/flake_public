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
        assert !(home.config.systemd.user.timers ? quaderno-transfer);
        assert
          system != "x86_64-linux"
          || ((purposeHome system "test-quaderno").config.systemd.user.timers ? quaderno-transfer);
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
            (builtins.elemAt (builtins.head packages.value)."$shellAppEnv" 2).QUADERNO_SERIAL == ""
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
        "quaderno"
      ];
    };

  quaderno-plan =
    (lib.lazyDerivation {
      derivation = (
        pkgs.runCommand "quaderno-plan" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          cp ${../../modules/home-manager/quaderno_plan.py} quaderno_plan.py
          cp ${../quaderno-plan.py} test_quaderno_plan.py
          python test_quaderno_plan.py
          touch "$out"
        ''
      );
    })
    // {
      elements = [ "quaderno" ];
    };
}
