# 行動: Web を見る。
requires = ["web_browsing"]

def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("bitwarden-desktop")})]
