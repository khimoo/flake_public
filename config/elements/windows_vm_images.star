# 目的: Windows の VM のディスクの置き場所。/var/lib/libvirt/images に、データ用ディスクの windows_vm_images_subvolume の subvol をマウントする。
# CoW のままだと VM のイメージが断片化するので、subvol には手で chattr +C を付け、compress は付けない（docs/architecture/disk-tiering.md）。
def config(host):
    return {"nixos": {("fileSystems", "/var/lib/libvirt/images"): {
        "device": host.data_device,
        "fsType": "btrfs",
        "options": ["subvol=" + host.windows_vm_images_subvolume, "noatime"],
    }}}
