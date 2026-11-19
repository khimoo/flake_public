# 手段: Hermes Desktop（Hermes Agent のデスクトップアプリ）を使う。
requires = ["llm_agents"]

def writes(gui_apps):
    return [write(gui_apps, pkg = pkg("hermes-desktop"), bin = "hermes-desktop", desktop = "hermes-desktop.desktop", mime = ["x-scheme-handler/hermes"], wayland = True)]
