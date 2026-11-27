requires = ["gui"]

# 目的: 日本語の入力（fcitx5 と Meltype）。
# Meltype はローマ字を打つだけで英語と日本語を見分ける。端末の Neovim は skkeleton（nvim_skkeleton.star）で打つ。
def user_config():
    return {"home": {
        "i18n.inputMethod.type": "fcitx5",
        "i18n.inputMethod.enable": True,
        "i18n.inputMethod.fcitx5.waylandFrontend": True,
        "i18n.inputMethod.fcitx5.addons": [pkg("fcitx5-gtk"), repoPkg("packages/meltype")],
        # 入力メソッドの一覧（~/.config/fcitx5/profile）。Home Manager は ~/.config/fcitx5 を丸ごと Nix のリンクにするので、
        # fcitx5 と設定画面はここに何も保存できない（全体の設定 config・アドオンの conf は fcitx5 の既定のまま）。変えるときはこのファイルを直す。
        # 1 つ目の keyboard-us は IME を切ったとき（Ctrl+Space）の配列、Meltype を既定にする。
        "i18n.inputMethod.fcitx5.settings.inputMethod": {
            "GroupOrder": {"0": "Default"},
            "Groups/0": {"Name": "Default", "Default Layout": "us", "DefaultIM": "meltype"},
            "Groups/0/Items/0": {"Name": "keyboard-us", "Layout": ""},
            "Groups/0/Items/1": {"Name": "meltype", "Layout": ""},
        },
    }}
