# 個人のファイルを置くアカウントのホームの個人フォルダを、データ用ディスクに載せる。
# subvol はアカウントごとに分け、名前をアカウント名から作る（@<アカウント名>-downloads など）。
when = ["personal_files", "has_data_disk"]

def user_config(user, host):
    mounts = {}
    for name, directory in [("downloads", "ダウンロード"), ("videos", "ビデオ"), ("music", "音楽"), ("pictures", "画像"), ("documents", "ドキュメント"), ("games", "Games")]:
        mounts[("fileSystems", user.home + "/" + directory)] = {
            "device": host.data_device,
            "fsType": "btrfs",
            "options": ["subvol=@" + user.name + "-" + name, "noatime", "compress=zstd"],
        }
    return {"nixos": mounts}
