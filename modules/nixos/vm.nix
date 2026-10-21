# libvirt の VM ホストの OS の設定、操作するユーザーの libvirtd グループ、Windows VM のランチャー
# （Home Manager の local.windowsVm）を一つの選択で切り替える。
{ config, lib, pkgs, settings, ... }:
let
  cfg = config.local.vm;
  homeUsers = map (u: u.username) (builtins.filter
    (u: (u.manageHome or true) && builtins.elem u.username cfg.users) settings.users);
in
{
  options.local.vm = {
    enable = lib.mkEnableOption "libvirt VM hosting";
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ settings.primaryUser ];
      description = "Users who join the libvirtd group and, if Home Manager manages them, get the Windows VM launcher.";
    };
    windowsDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "libvirt domain of the Windows VM. Null installs no launcher.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.spiceUSBRedirection.enable = true;
    virtualisation.libvirtd = {
      enable = true;
      # UEFI対応などのためのQEMU設定
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        vhostUserPackages = [ pkgs.virtiofsd ];
      };
    };
    environment.etc = {
      "ovmf/edk2-x86_64-secure-code.fd" = {
        source = "${pkgs.qemu_kvm}/share/qemu/edk2-x86_64-secure-code.fd";
      };
      "ovmf/edk2-i386-vars.fd" = {
        source = "${pkgs.qemu_kvm}/share/qemu/edk2-i386-vars.fd";
      };
    };

    # virt-manager (GUIでのVM管理用)
    programs.virt-manager.enable = true;

    # qemu/kvmなどで使う"default"というNICを自動で起動させる
    systemd.services.libvirt-network-autostart = {
      description = "Enable autostart for libvirt default network";
      after = [ "libvirtd.service" ];
      requires = [ "libvirtd.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.libvirt}/bin/virsh net-autostart default";
        RemainAfterExit = "yes";
      };
    };
    users.users = lib.genAttrs cfg.users (_: { extraGroups = [ "libvirtd" ]; });
    home-manager.users = lib.mkIf (cfg.windowsDomain != null) (lib.genAttrs homeUsers (_: {
      local.windowsVm = {
        enable = true;
        domain = cfg.windowsDomain;
      };
    }));
  };
}
