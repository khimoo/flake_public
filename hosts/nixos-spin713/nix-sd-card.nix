# /nix を SD カードに置くことに由来する設定。非力なマシンであることに由来する設定（リモートビルドなど）は default.nix に置く。
# /nix は NixOS が起動に必要なパスとして initrd でマウントするので、サービスに nix.mount への依存を足さない。
{ ... }:
let
  nixUuid = "35e48f86-290c-43f3-9567-f677f2f98a4e";
in
{
  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/${nixUuid}";
    fsType = "ext4";
  };

  # 復帰直後にカードリーダーが返す media change で、/nix の読み出しが拒否されるのを避ける。
  # 理由と効果の確かめ方: docs/architecture/spin713-sd-resume.md
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_FS_UUID}=="${nixUuid}", ATTRS{idVendor}=="05e3", ATTRS{idProduct}=="0747", ATTR{../device/scsi_disk/*/manage_system_start_stop}="1"
  '';
}
