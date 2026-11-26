# 目的: ログイン画面。GDM から Niri のセッションを選んで入る。
requires = ["niri"]
needs = ["nixos_system"]

def config(xkb):
    return {"nixos": {
        "services.xserver.enable": True,
        "services.displayManager.gdm.enable": True,
        # Niri を既定のセッションにする。programs.niri も mkDefault で同じ値を入れるが、選択の結果をここで読めるようにする。
        "services.displayManager.defaultSession": "niri",
        "services.xserver.xkb.layout": xkb.layout,
        "services.xserver.xkb.variant": xkb.variant,
    }}
