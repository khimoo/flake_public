# 行動（仕事、勉強、趣味、生活管理）: Web を見る。
requires = ["category_work", "category_study", "category_hobby", "web_browsing"]

def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("bitwarden-desktop")})]
