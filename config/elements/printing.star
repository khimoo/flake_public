def config():
    return {"nixos": {
        "services.printing.enable": True,
        "services.printing.drivers": [pkg("gutenprint")],
        "services.avahi.enable": True,
        "services.avahi.nssmdns4": True,
        "services.avahi.openFirewall": True,
    }}
