def config():
    return {"nixos": {
        "boot.loader.systemd-boot.enable": True,
        "boot.loader.efi.canTouchEfiVariables": True,
        "boot.tmp.cleanOnBoot": True,
    }}
