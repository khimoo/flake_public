def config():
    return {"nixos": {
        "networking.networkmanager.enable": True,
        # KDE Connect / GSConnect が使うポート。
        "networking.firewall.allowedTCPPortRanges": [{"from": 1714, "to": 1764}],
        "networking.firewall.allowedUDPPortRanges": [{"from": 1714, "to": 1764}],
    }}
