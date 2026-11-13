# 目的: xsaved のデータ置き場。[xsaved_users.<利用者>] の data_dir に、データ用ディスクの data_subvolume の subvol をマウントする。
def user_config(user, host):
    values = host.xsaved_users[user.name]
    # 手で subvol を作る前でも起動できるよう nofail にする。書き込み前の mount 確認は xsaved が行う（check_mount）。
    return {"nixos": {("fileSystems", values["data_dir"]): {
        "device": host.data_device,
        "fsType": "btrfs",
        "options": ["subvol=" + values["data_subvolume"], "noatime", "compress=zstd", "nofail"],
    }}}
