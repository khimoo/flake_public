# 行動: プログラムを書く。
requires = ["dev_tools", "ai_agents"]

def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("typst")})]
