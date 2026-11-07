when = ["dev_tools", "gui"]

def config():
    return {"home": {"home.packages": [
        pkg("vscode"),
        pkg("jetbrains.idea"),
        pkg("android-tools"),
    ]}}
