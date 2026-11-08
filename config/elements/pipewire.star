def config():
    return {"nixos": {
        "services.pulseaudio.enable": False,
        "security.rtkit.enable": True,
        "services.pipewire.enable": True,
        "services.pipewire.alsa.enable": True,
        "services.pipewire.pulse.enable": True,
        "services.pipewire.wireplumber.enable": True,
    }}
