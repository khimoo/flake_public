kind = "machine"
requires = ["x86_64_linux", "nixos_system", "rocm_compute", "local_kvm", "personal_pc"]

def config(host):
    primary = host.users[0]["name"]
    home = "/home/" + primary
    data_opts = ["noatime", "compress=zstd"]
    mounts = []
    for subvol, directory in [("downloads", "ダウンロード"), ("videos", "ビデオ"), ("music", "音楽"), ("pictures", "画像"), ("documents", "ドキュメント"), ("games", "Games")]:
        mounts.append(("@" + subvol, home + "/" + directory, data_opts))
    mounts.extend([
        ("@backup", host.backup_dir, data_opts),
    ])
    nixos = {
        "boot.kernelParams": ["btusb.enable_autosuspend=n"],
        "programs.steam.enable": True,
        # Steam の 32bit のゲームの音のため。pipewire 要素に置くと、ゲームをしない spin713 にも 32bit 版の PipeWire が入る。
        "services.pipewire.alsa.support32Bit": True,
        "fileSystems": {path: {"device": host.data_device, "fsType": "btrfs", "options": ["subvol=" + subvol] + opts} for subvol, path, opts in mounts},
        "boot.supportedFilesystems": ["btrfs"],
        "environment.systemPackages": [pkg("btrfs-progs")],
        "services.keyd": {"enable": True, "keyboards": {"default": {
            "ids": ["*"],
            "settings": {"meta": {"rightalt": "toggle(turbo)"}, "turbo": {"rightalt": "macro2(%s, %s, macro(rightmouse))" % (host.turbo_interval_ms, host.turbo_interval_ms)}},
        }}},
    }
    return {"nixos_imports": [repoModule("hosts/nixos-desktop/hardware.nix")], "nixos": nixos}

def user_config():
    return {"home": {
        "home.packages": [pkg("wine64"), pkg("pkgsRocm.blender"), pkg("gnomeExtensions.display-configuration-switcher")],
        ("dconf", "settings", "org/gnome/shell", "enabled-extensions"): mkAfter(["display-configuration-switcher@knokelmaat.gitlab.com"]),
    }}
