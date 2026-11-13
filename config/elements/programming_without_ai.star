# 行動: AI を使わずにプログラムを書く（AI を使えない会社の機体で選ぶ）。AI を使える職場になったら、この要素を消して programming を選ぶ。
requires = ["web_browsing", "temp_storage", "shell", "git", "daily_editing", "dev_tools", "task_management", "use_uv"]

def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("typst")})]
