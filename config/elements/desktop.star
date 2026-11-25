# 目的: 自分で操作する PC のデスクトップ（ログイン画面、Niri、統合シェル DMS、アイドル制御、ディスプレイ配置、見た目）。
# 単機能ツールの定義（waybar / swaync / vicinae / swaylock 等）は比較・ロールバック用に config/elements/ へ残している。
requires = ["gdm", "niri_config", "dms_shell", "swayidle", "display_layout", "desktop_appearance", "niri_background_apps", "niri_floating_toggle"]
needs = ["nixos_system"]

def config(gui):
    return {"nixos": {
        "environment.systemPackages": [pkg("gparted")],
        # Home Manager を使わないユーザー（mase）や GDM でも DejaVu へ落ちないよう、システム既定のフォントも同じ組にする。
        "fonts.packages": gui.font_packages,
        "fonts.fontconfig.defaultFonts": gui.default_fonts,
    }}
