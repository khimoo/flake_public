# 行動: 日常の作業（付箋のメモ）。
def writes(gui_apps):
    return [write(gui_apps, app) for app in [
        {"pkg": pkg("sticky-notes"), "name": "sticky-notes", "bin": "com.vixalien.sticky", "desktop": "com.vixalien.sticky.desktop", "autostart": True},
    ]]
