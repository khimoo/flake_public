requires = ["x86_64_linux", "machine_base", "systemd_boot", "network_manager", "machine_ssh", "tailscale", "pipewire"]

def config(host, tailscale):
    primary = host.users[0]["name"]
    home = "/home/" + primary
    data_opts = ["noatime", "compress=zstd"]
    mounts = []
    for subvol, directory in [("downloads", "ダウンロード"), ("videos", "ビデオ"), ("music", "音楽"), ("pictures", "画像"), ("documents", "ドキュメント"), ("games", "Games")]:
        mounts.append(("@" + subvol, home + "/" + directory, data_opts))
    mounts.extend([
        ("@backup", host.backup_dir, data_opts),
        ("@vm", "/var/lib/libvirt/images", ["noatime"]),
        # 手で subvol を作る前でも起動できるよう nofail にする。書き込み前の mount 確認は各アプリが行う。
        ("@mimikopi", host.mimikopi_data_dir, data_opts + ["nofail"]),
        ("@xsaved", host.xsaved_users[primary]["data_dir"], data_opts + ["nofail"]),
    ])
    nixos = {
        "boot.kernelParams": ["btusb.enable_autosuspend=n"],
        # 外出先から起こす手段がないため、ログイン画面でもセッション内でも自動 suspend させない。
        "services.displayManager.gdm.autoSuspend": False,
        "services.desktopManager.gnome.extraGSettingsOverrides": "[org.gnome.settings-daemon.plugins.power]\nsleep-inactive-ac-type='nothing'\n",
        ("users", "users", primary, "linger"): True,
        ("networking", "firewall", "interfaces", tailscale.interface, "allowedTCPPortRanges"): [{"from": 3389, "to": 3399}],
        # linked 状態では GNOME 設定が RDP の項目を隠すため、ユニットを enabled にする。
        "systemd.services.gnome-remote-desktop.wantedBy": ["graphical.target"],
        "programs.steam.enable": True,
        # Steam の 32bit のゲームの音のため。pipewire 要素に置くと、ゲームをしない spin713 にも 32bit 版の PipeWire が入る。
        "services.pipewire.alsa.support32Bit": True,
        "fileSystems": {path: {"device": host.data_device, "fsType": "btrfs", "options": ["subvol=" + subvol] + opts} for subvol, path, opts in mounts},
        "systemd.tmpfiles.rules": ["d " + host.backup_dir + "/" + app + " 0755 " + primary + " users -" for app in ["minecraft", "quaderno"]],
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
        "home.packages": [pkg("prismlauncher"), pkg("wine64"), pkg("pkgsRocm.blender"), pkg("gnomeExtensions.display-configuration-switcher")],
        ("dconf", "settings", "org/gnome/shell", "enabled-extensions"): mkAfter(["display-configuration-switcher@knokelmaat.gitlab.com"]),
    }}
