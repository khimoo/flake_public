# 利用目的（趣味）: 絵や図を描く。
requires = ["inkscape", "temp_storage", "use_ai_agents"]

def writes(gui_apps):
    return [
        write(gui_apps, pkg = pkg("krita")),
        write(gui_apps, pkg = inputPkg("rnote", "default")),
        write(gui_apps, pkg = pkg("mypaint")),
    ]
