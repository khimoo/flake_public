# 利用目的（趣味）: プログラムを書く。
requires = ["web_browsing", "temp_storage", "shell", "git", "daily_editing", "dev_tools", "task_management", "use_ai_agents"]

def writes(gui_apps):
    return [write(gui_apps, pkg = pkg("typst"))]
