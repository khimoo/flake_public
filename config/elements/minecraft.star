# 手段: Minecraft で遊ぶ（Prism Launcher と、インスタンスのバックアップ）。
requires = ["minecraft_backup"]

def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("prismlauncher")})]
