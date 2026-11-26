requires = ["gui"]

# 目的: 日本語の入力（fcitx5 と Meltype）。
# Meltype はローマ字を打つだけで英語と日本語を見分ける。端末の Neovim は skkeleton（nvim_skkeleton.star）で打つ。
def user_config():
    return {"home": {
        "i18n.inputMethod.type": "fcitx5",
        "i18n.inputMethod.enable": True,
        "i18n.inputMethod.fcitx5.waylandFrontend": True,
        "i18n.inputMethod.fcitx5.addons": [pkg("fcitx5-gtk"), repoPkg("packages/meltype")],
    }}
