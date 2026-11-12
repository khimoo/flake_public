requires = ["gui"]

# 目的: 日本語の入力（fcitx5 と SKK）。
def user_config():
    return {"home": {
        "i18n.inputMethod.type": "fcitx5",
        "i18n.inputMethod.enable": True,
        "i18n.inputMethod.fcitx5.waylandFrontend": True,
        "i18n.inputMethod.fcitx5.addons": [pkg("fcitx5-gtk"), pkg("fcitx5-skk")],
    }}
