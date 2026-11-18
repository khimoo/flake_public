# 目的: xsaved のデータ置き場。ユーザーの data_dir に、データ用ディスクの subvol（ユーザーの表の data_subvolume）をマウントする。
needs = ["has_data_disk"]

def user_config(host, serve_xsaved):
    if "data_subvolume" not in serve_xsaved.values:
        fail("xsaved_data: user selects xsaved_data but has no data_subvolume in [users.xsaved]")
    if not serve_xsaved.check_mount:
        fail("xsaved_data: check_mount must be true when mounting data_subvolume")
    # 手で subvol を作る前でも起動できるよう nofail にする。書き込み前の mount 確認は xsaved が行う（check_mount）。
    return {"nixos": {("fileSystems", serve_xsaved.data_dir): {
        "device": host.data_device,
        "fsType": "btrfs",
        "options": ["subvol=" + serve_xsaved.values["data_subvolume"], "noatime", "compress=zstd", "nofail"],
    }}}
