# 道具: 付箋（sticky-notes）。タスク管理と文書の一時保管の両方に使う。
def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("sticky-notes"), "name": "sticky-notes", "bin": "com.vixalien.sticky", "desktop": "com.vixalien.sticky.desktop", "autostart": True})]
