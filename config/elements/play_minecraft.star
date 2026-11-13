# 行動: Minecraft で遊ぶ（Prism Launcher と、インスタンスのバックアップ）。
requires = ["minecraft_backup", "temp_storage"]

def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("prismlauncher")})]
