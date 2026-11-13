# 行動（仕事、趣味）: プログラムを書く。
requires = ["category_work", "category_hobby", "shell", "git", "daily_editing", "dev_tools", "ai_agents"]

def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("typst")})]
