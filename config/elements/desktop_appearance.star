# 目的: ユーザーのデスクトップの見た目（暗い配色）。GTK のアプリと portal は dconf の color-scheme を読む。
# 画面の拡大率はコンポジタ（Niri の出力 scale）側で扱うため、二重拡大を避けて text-scaling-factor は 1.0 に固定する。
requires = ["gui"]
needs = ["linux"]

def user_config():
    interface = {
        "color-scheme": "prefer-dark",
        "accent-color": "blue",
        "text-scaling-factor": 1.0,
        "toolkit-accessibility": False,
    }
    return {"home": {
        "dconf.enable": True,
        "dconf.settings": {"org/gnome/desktop/interface": interface},
        "gtk.enable": True,
        "gtk.colorScheme": "dark",
        # Wayland / GTK / XWayland でリンク上の指マークなど標準のカーソル形状が切り替わるようにする。
        "home.pointerCursor": {
            "enable": True,
            "package": pkg("adwaita-icon-theme"),
            "name": "Adwaita",
            "size": 24,
            "gtk": {"enable": True},
            "x11": {"enable": True},
        },
    }}
