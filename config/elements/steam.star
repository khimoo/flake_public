# 手段: Steam でゲームをする。
needs = ["nixos_system"]
requires = ["pipewire"]

def config():
    return {"nixos": {
        "programs.steam.enable": True,
        "hardware.graphics.enable32Bit": True,
        # Steam の 32bit のゲームの音のため。pipewire のコンポーネントに置くと、ゲームをしないホストにも 32bit 版の PipeWire が入る。
        "services.pipewire.alsa.support32Bit": True,
    }}
