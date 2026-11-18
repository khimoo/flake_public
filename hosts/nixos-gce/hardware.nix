{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/virtualisation/google-compute-config.nix")
  ];

  # GCE の Shielded VM（既定）は UEFI で起動し、マシン系列によって sda（virtio-scsi）または nvme0n1 になる。
  # google-compute-config.nix の /dev/disk/by-label/nixos と合わせて、デバイス名ではなくラベルでマウントする。
  boot.initrd.availableKernelModules = [ "nvme" ];
  boot.loader.grub = {
    device = lib.mkForce "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
    configurationLimit = lib.mkForce 5;
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  networking.useDHCP = lib.mkDefault true;

  # google-compute-config.nix は OS Login を有効にし、NixOS のファイアウォールを既定で無効にする。
  # このリポジトリではユーザーと公開鍵（authorize_lan_key）を宣言的に管理し、パスワードを持たない管理者が
  # id_lan でログインして sudo や --target-host switch を行えるようにする。
  security.googleOsLogin.enable = lib.mkForce false;
  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [ "@wheel" ];
  networking.firewall.enable = true;

  # nixos-anywhere --flake .#nixos-gce が kexec 後に実行するディスク初期化スクリプト。
  # GCE はブート用の永続ディスクを /dev/disk/by-id/google-persistent-disk-0 に出すため、まずそれを選び、
  # Local SSD（nvme）を誤って初期化しないようにする。
  system.build.diskoScript = pkgs.writeShellScript "gce-disko" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.dosfstools
        pkgs.e2fsprogs
        pkgs.parted
        pkgs.systemd
        pkgs.util-linux
      ]
    }:$PATH
    if [ -e /dev/disk/by-id/google-persistent-disk-0 ]; then
      disk=$(readlink -f /dev/disk/by-id/google-persistent-disk-0)
    elif [ -b /dev/sda ]; then
      disk=/dev/sda
    elif [ -b /dev/nvme0n1 ]; then
      disk=/dev/nvme0n1
    else
      echo "gce-disko: boot disk not found" >&2
      exit 1
    fi
    case "$disk" in
      *[0-9])
        part1="''${disk}p1"
        part2="''${disk}p2"
        ;;
      *)
        part1="''${disk}1"
        part2="''${disk}2"
        ;;
    esac
    umount -R /mnt 2>/dev/null || true
    wipefs -a "$disk"
    parted -s "$disk" -- mklabel gpt \
      mkpart ESP fat32 1MiB 513MiB \
      set 1 esp on \
      mkpart nixos ext4 513MiB 100%
    udevadm settle
    mkfs.vfat -F 32 -n ESP "$part1"
    mkfs.ext4 -F -L nixos "$part2"
    mkdir -p /mnt
    mount -t ext4 "$part2" /mnt
    mkdir -p /mnt/boot
    mount -t vfat -o umask=0077 "$part1" /mnt/boot
  '';
  system.build.diskoScriptNoDeps = config.system.build.diskoScript;
}
