# libvirt ネットワーク自動起動設定
{ pkgs, ... }: {
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
}
