# 目的: 自分で操作する PC のデスクトップ（ログイン画面、Niri、バー、通知、ランチャー、ロック、トレイ、音、背景、ディスプレイの配置、見た目）。
requires = ["gdm", "niri_config", "waybar", "swaync", "vicinae", "swaylock", "swayidle", "nm_applet", "blueman_applet", "audio_controls", "swaybg", "display_layout", "desktop_appearance", "niri_background_apps", "niri_floating_toggle"]
needs = ["nixos_system"]

def config(gui):
    return {"nixos": {
        "environment.systemPackages": [pkg("gparted")],
        # Home Manager を使わないユーザー（mase）や GDM でも DejaVu へ落ちないよう、システム既定のフォントも同じ組にする。
        "fonts.packages": gui.font_packages,
        "fonts.fontconfig.defaultFonts": gui.default_fonts,
    }}
