kind = "machine"
requires = ["x86_64_linux", "nixos_system", "rocm_compute", "local_kvm", "has_data_disk", "personal_pc"]

def config(host):
    data_opts = ["noatime", "compress=zstd"]
    mounts = [("@backup", host.backup_dir, data_opts)]
    nixos = {
        "boot.kernelParams": ["btusb.enable_autosuspend=n"],
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
        "home.packages": [pkg("gnomeExtensions.display-configuration-switcher")],
        ("dconf", "settings", "org/gnome/shell", "enabled-extensions"): mkAfter(["display-configuration-switcher@knokelmaat.gitlab.com"]),
    }}
