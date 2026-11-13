needs = ["x86_64_linux", "rocm_compute"]

def config(host):
    # 手で subvol を作る前でも起動できるよう nofail にする。書き込み前の mount 確認は mimikopi が行う。
    return {"nixos": {("fileSystems", host.mimikopi_data_dir): {"device": host.data_device, "fsType": "btrfs", "options": ["subvol=" + host.mimikopi_data_subvolume, "noatime", "compress=zstd", "nofail"]}}}

def user_config(host):
    return {"home": {"home.packages": [repoPkgWith("packages/mimikopi-env", {
        "dataDir": host.mimikopi_data_dir,
        "hsaOverrideGfxVersion": getattr(host, "mimikopi_hsa_override", None),
    })]}}
