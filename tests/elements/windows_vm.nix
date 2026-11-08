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
    purposeHome
    rejectsPurpose
    allAssertions
    ;
in
{
  windows_vm-contracts =
    (lib.lazyDerivation {
      derivation = (
        # GUI のないユーザーでは Windows VM のランチャーの評価を止める。
        assert rejectsPurpose "test-windows-vm-no-gui" "x86_64-linux" "windows_vm: launcher requires gui";
        assert system != "x86_64-linux" || allAssertions (purposeHome system "test-windows-vm");
        pkgs.runCommand "windows_vm-contracts" { } ''
          echo "windows_vm contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [
        "checkout"
        "firefox"
        "gui"
        "gui_apps"
        "inkscape"
        "kitty"
        "teams_dispatcher"
        "windows_vm"
        "windows_vm_gui"
      ];
    };
  # windows-vm の起動、待機、ロック、止め忘れの通知を、偽の virsh と FreeRDP で確かめる。
  # flock は util-linux にしかなく、ランチャー自体も Linux 専用なので、Darwin では省く。
  windows-vm =
    (lib.lazyDerivation {
      derivation = (
        if system != "x86_64-linux" then
          pkgs.runCommand "windows-vm-skipped" { } "touch $out"
        else
          pkgs.runCommand "windows-vm"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.util-linux
              ];
            }
            ''
              python ${../windows-vm.py} ${../../modules/home-manager/windows-vm.sh}
              touch "$out"
            ''
      );
    })
    // {
      elements = [ "windows_vm" ];
    };
  # windows-vm のビルド（writeShellApplication の shellcheck）を CI で通す。
  # デスクトップの構成は評価しかしないので、ここでビルドしないと見つからない。
  windows-vm-package =
    (lib.lazyDerivation {
      derivation = (
        if system != "x86_64-linux" then
          pkgs.runCommand "windows-vm-package-skipped" { } "touch $out"
        else
          lib.findFirst (
            p: (p.name or "") == "windows-vm"
          ) (throw "windows-vm is not installed") (purposeHome system "test-windows-vm").config.home.packages
      );
    })
    // {
      elements = [
        "windows_vm"
        "windows_vm_gui"
      ];
    };
}
