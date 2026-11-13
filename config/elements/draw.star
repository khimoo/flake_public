# 行動（趣味）: 絵や図を描く。
requires = ["category_hobby", "inkscape"]

def writes(gui_apps):
    return [write(gui_apps, app) for app in [
        {"pkg": pkg("krita")},
        {"pkg": inputPkg("rnote", "default")},
        {"pkg": pkg("mypaint")},
    ]]
