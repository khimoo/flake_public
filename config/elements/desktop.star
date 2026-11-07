def config():
    return {"nixos": {
        "services.xserver.enable": True,
        "services.displayManager.gdm.enable": True,
        "services.desktopManager.gnome.enable": True,
        "services.xserver.xkb.layout": "us",
        "services.xserver.xkb.variant": "",
        "environment.systemPackages": [pkg("gparted")],
    }}
