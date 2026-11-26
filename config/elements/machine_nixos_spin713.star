kind = "machine"
requires = ["x86_64_linux", "nixos_system", "has_orientation_sensor", "personal_pc", "iio_niri", "remote_build"]

def config(host):
    return {"nixos_imports": [repoModule("hosts/nixos-spin713/hardware.nix")], "nixos": {
        "zramSwap.enable": True,
        "hardware.graphics.extraPackages": [pkg("intel-media-driver")],
        ("fileSystems", "/nix"): {"device": "/dev/disk/by-uuid/" + host.nix_uuid, "fsType": "ext4"},
        # 復帰直後の media change で /nix が読めなくなるのを防ぐ（docs/architecture/spin713-sd-resume.md）。
        "services.udev.extraRules": 'ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_FS_UUID}=="' + host.nix_uuid + '", ATTRS{idVendor}=="05e3", ATTRS{idProduct}=="0747", ATTR{../device/scsi_disk/*/manage_system_start_stop}="1"\n',
        "boot.kernelParams": ["mem_sleep_default=s2idle"],
        "services.logind.settings.Login": {"HandleLidSwitch": "suspend-then-hibernate", "HandleLidSwitchDocked": "suspend", "HandleLidSwitchExternalPower": "ignore"},
        "systemd.sleep.settings.Sleep.HibernateDelaySec": "10m",
        "swapDevices": [{"device": host.swap_device}],
        "boot.resumeDevice": host.swap_device,
        "boot.extraModprobeConfig": "options snd-intel-dspcfg dsp_driver=4\n",
        ("environment", "etc", "libinput/local-overrides.quirks", "text"): "[Serial Keyboards]\nMatchUdevType=keyboard\nMatchName=keyd virtual keyboard\nAttrKeyboardIntegration=internal\n",
        "environment.systemPackages": [pkg("sof-firmware"), pkg("alsa-utils")],
    }}

def writes(keyd, host):
    # 内蔵キーボードに ChromeOS 配列再現と Super 単押しを適用し、既定キーボード（外付け向け）から内蔵 ID を除外する。
    return [write(
        keyd,
        extra_keyboards = {
            "internal": {"ids": host.keyd_ids, "settings": host.keyd_settings},
        },
        exclude_default_ids = host.keyd_ids,
    )]
