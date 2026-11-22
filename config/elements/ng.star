needs = ["linux"]
requires = ["neovim", "japanese_input"]

def writes(gui_apps):
    return [write(gui_apps, pkg = repoPkg("packages/ng"))]

def user_config():
    return {"home": {"home.packages": [pkg("wl-clipboard"), pkg("xclip")]}}
