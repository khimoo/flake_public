def config():
    return {"nixos": {
        "hardware.bluetooth.enable": True,
        "hardware.bluetooth.powerOnBoot": True,
        "hardware.bluetooth.settings": {
            "General": {
                "Enable": "Source,Sink,Media,Socket",
                "ControllerMode": "dual",
                "FastConnectable": "true",
                "Experimental": "true",
            },
            "Policy": {"AutoEnable": "true"},
        },
    }}
