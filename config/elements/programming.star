# 行動: プログラムを書く。
# xsaved は requires に挙げない。[xsaved_users.<利用者>] の値がない利用者が programming を選ぶと、confgen がエラーにする。
requires = ["web_browsing", "temp_storage", "shell", "git", "daily_editing", "dev_tools", "ai_agents"]

def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("typst")})]
