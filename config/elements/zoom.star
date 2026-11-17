# 手段: Zoom でビデオ会議をする。
def writes(gui_apps):
    return [write(gui_apps, pkg = pkg("zoom-us"), desktop = "Zoom.desktop", mime = ["x-scheme-handler/zoommtg", "x-scheme-handler/zoomus"])]
