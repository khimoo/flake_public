needs = ["nixos_system"]

def config():
    return {"nixos": {
        "boot.initrd.kernelModules": ["v4l2loopback"],
        "boot.extraModulePackages": [kernelPkg("v4l2loopback")],
        "environment.systemPackages": [pkg("droidcam")],
    }}
