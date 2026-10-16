# libvirt の Windows VM を、使うときだけ起動して FreeRDP で表示する。
#
#   windows-vm connect   止まっていれば起動し、RDP が応答するまで待って接続する（既定）
#   windows-vm shutdown  ACPI のシャットダウンを要求する
#   windows-vm console   USB リダイレクト用に virt-manager で SPICE の画面を開く
#
# VM の Windows でリモートデスクトップを有効にし、NLA を切っておく必要がある。
# 設計判断: docs/architecture/windows-vm.md
# 使い方:   docs/howtouse/windows-vm.md
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.windowsVm;

  # 右 Alt の直後のショートカット一回だけキーボードを掴むよう、パッチを当てた FreeRDP を使う。
  freerdpGrabOnce = pkgs.callPackage ../../packages/freerdp-grab-once { };

  windows-vm = pkgs.writeShellApplication {
    name = "windows-vm";
    runtimeInputs = with pkgs; [
      coreutils
      freerdpGrabOnce
      libnotify
      libsecret
      libvirt
      util-linux
      virt-manager
    ];
    runtimeEnv = {
      WINDOWS_VM_DOMAIN = cfg.domain;
      WINDOWS_VM_BOOT_TIMEOUT = toString cfg.bootTimeoutSeconds;
    };
    text = builtins.readFile ./windows-vm.sh;
  };
  launcher = lib.getExe windows-vm;
in
{
  options.local.windowsVm = {
    enable = lib.mkEnableOption "libvirt の Windows VM を FreeRDP で使うランチャー";

    domain = lib.mkOption {
      type = lib.types.str;
      description = ''
        qemu:///system にある VM のドメイン名（`virsh list --all` の Name）。
        VM ごとに違うので既定値は置かず、呼び出し側で指定する。
      '';
    };

    bootTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 600;
      description = ''
        VM を起動してから RDP（3389 番ポート）が応答するまで待つ上限。
        Windows Update を適用する起動は数分かかるので、それを待てる長さにしている。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.local.profile.features.gui;
        message = "local.windowsVm: requires local.profile.features.gui (it adds a desktop launcher)";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "local.windowsVm: libvirt and the launcher are supported only on Linux";
      }
    ];

    home.packages = [ windows-vm ];

    # 右 Alt の単独押しで、次のショートカット一回だけキーボードを Windows に渡す。普段はホストに残す。
    # ホットキーは押された時点の修飾キーが SDL_KeyModMask を含めば発動するので、修飾キー自身を指定できる。
    # 右 Alt は配列で AltGr（ISO_Level3_Shift）になっていて、SDL は KMOD_RALT ではなく KMOD_MODE を立てる。
    # 理由と代償は docs/architecture/windows-vm.md。
    xdg.configFile."freerdp/sdl-freerdp.json".text = builtins.toJSON {
      SDL_KeyModMask = [ "KMOD_MODE" ];
      SDL_Grab = "SDL_SCANCODE_RALT";
    };

    xdg.desktopEntries.windows-vm = {
      name = "Windows";
      comment = "VM の Windows を起動して FreeRDP で接続する";
      exec = "${launcher} connect";
      icon = "computer";
      terminal = false;
      categories = [ "System" ];
      actions = {
        shutdown = {
          name = "シャットダウン";
          exec = "${launcher} shutdown";
        };
        console = {
          name = "SPICE で開く";
          exec = "${launcher} console";
        };
      };
    };
  };
}
