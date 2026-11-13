# 手段: Steam でゲームをする。
needs = ["nixos_system"]
requires = ["pipewire"]

def config():
    return {"nixos": {
        "programs.steam.enable": True,
        # Steam の 32bit のゲームの音のため。pipewire の要素に置くと、ゲームをしない機体にも 32bit 版の PipeWire が入る。
        "services.pipewire.alsa.support32Bit": True,
    }}
