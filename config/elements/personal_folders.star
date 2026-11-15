# ユーザーのホームの個人フォルダを、データ用ディスクに載せる。
# subvol はユーザーごとに分け、名前をユーザー名から作る（@<ユーザー名>-downloads など）。
needs = ["has_data_disk"]

def user_config(user, host):
    mounts = {}
    for name, directory in [("downloads", "ダウンロード"), ("videos", "ビデオ"), ("music", "音楽"), ("pictures", "画像"), ("documents", "ドキュメント"), ("games", "Games")]:
        mounts[("fileSystems", user.home + "/" + directory)] = {
            "device": host.data_device,
            "fsType": "btrfs",
            "options": ["subvol=@" + user.name + "-" + name, "noatime", "compress=zstd"],
        }
    return {"nixos": mounts}
