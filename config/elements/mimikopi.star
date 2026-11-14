needs = ["x86_64_linux", "rocm_compute"]

def user_config(host, user):
    data = user.home + "/.local/share/mimikopi"
    return {
        "home": {"home.packages": [repoPkgWith("packages/mimikopi-env", {
            "dataDir": data,
            "hsaOverrideGfxVersion": getattr(host, "mimikopi_hsa_override", None),
        })]},
        # 手で subvol を作る前でも起動できるよう nofail にする。書き込み前の mount 確認は mimikopi が行う。
        "nixos": {("fileSystems", data): {"device": host.data_device, "fsType": "btrfs", "options": ["subvol=" + host.mimikopi_data_subvolume, "noatime", "compress=zstd", "nofail"]}},
    }
