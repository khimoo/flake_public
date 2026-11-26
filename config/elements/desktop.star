# 目的: 自分で操作する PC のデスクトップ（ログイン画面、Niri、Quickshell ハブ、ロック、トレイ、音、背景、ディスプレイの配置、見た目）。
# 未使用の単機能 UI 定義（waybar / swaync / vicinae）は比較・ロールバック用に config/elements/ へ残している。
requires = ["gdm", "keyd", "niri_config", "quickshell_hub", "swaylock", "swayidle", "nm_applet", "blueman_applet", "audio_controls", "swaybg", "display_layout", "desktop_appearance", "niri_background_apps", "niri_floating_toggle"]
needs = ["nixos_system"]

def config(gui):
    return {"nixos": {
        "environment.systemPackages": [pkg("gparted")],
        # Home Manager を使わないユーザー（mase）や GDM でも DejaVu へ落ちないよう、システム既定のフォントも同じ組にする。
        "fonts.packages": gui.font_packages,
        "fonts.fontconfig.defaultFonts": gui.default_fonts,
    }}
