# 目的: Obsidian で memex の vault を開く。
def writes(memex):
    return [write(memex, {"obsidian": True})]

def config():
    return {"home": {("xdg", "mimeApps", "defaultApplications", "x-scheme-handler/obsidian"): "obsidian.desktop"}}
