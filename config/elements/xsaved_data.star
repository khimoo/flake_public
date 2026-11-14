# 目的: xsaved のデータ置き場。利用者の data_dir に、データ用ディスクの subvol（利用者の表の data_subvolume）をマウントする。
def user_config(host, serve_xsaved):
    # 手で subvol を作る前でも起動できるよう nofail にする。書き込み前の mount 確認は xsaved が行う（check_mount）。
    return {"nixos": {("fileSystems", serve_xsaved.data_dir): {
        "device": host.data_device,
        "fsType": "btrfs",
        "options": ["subvol=" + serve_xsaved.values["data_subvolume"], "noatime", "compress=zstd", "nofail"],
    }}}
