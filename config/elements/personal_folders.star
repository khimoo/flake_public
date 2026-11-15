# ユーザーのホームの個人フォルダを、データ用ディスクに載せる。
# btrfs の subvol= は subvol の根しか指せないので、subvol をホームへ直接マウントする形では、ユーザーを足すたびに
# subvol を手で作ることになる。
needs = ["has_data_disk"]

_SUBVOLUME = "@personal"
_ROOT = "/mnt/personal"
_FOLDERS = [("downloads", "ダウンロード"), ("videos", "ビデオ"), ("music", "音楽"), ("pictures", "画像"), ("documents", "ドキュメント"), ("games", "Games")]

def config(host):
    return {"nixos": {("fileSystems", _ROOT): {
        "device": host.data_device,
        "fsType": "btrfs",
        "options": ["subvol=" + _SUBVOLUME, "noatime", "compress=zstd"],
    }}}

def user_config(user):
    base = _ROOT + "/" + user.name
    service = "personal-folders-" + user.name
    lines = ['[ -e "%s" ] || install -d -m 0700 -o %s -g users "%s"\n' % (base, user.name, base)]
    for name, _ in _FOLDERS:
        lines.append('[ -e "%s/%s" ] || install -d -m 0755 -o %s -g users "%s/%s"\n' % (base, name, user.name, base, name))
    nixos = {
        # bind mount の元のディレクトリがないとマウントが失敗し、起動が緊急モードで止まる。tmpfiles は
        # local-fs.target の後に実行されて間に合わないので、マウントの前にこのサービスで作る。
        # 既にあるディレクトリの所有者とパーミッションは変えない。
        ("systemd", "services", service): {
            "description": "Create the personal folders of " + user.name + " on the data disk",
            "unitConfig": {"DefaultDependencies": False, "RequiresMountsFor": _ROOT},
            "serviceConfig": {"Type": "oneshot", "RemainAfterExit": True},
            "script": "".join(lines),
        },
    }
    for name, directory in _FOLDERS:
        nixos[("fileSystems", user.home + "/" + directory)] = {
            "device": base + "/" + name,
            "fsType": "none",
            "options": ["bind", "x-systemd.requires=" + service + ".service"],
        }
    return {"nixos": nixos}
