when = ["dev_tools", "gui"]

def config():
    return {"home": {"home.packages": [
        pkg("jetbrains.idea"),
        pkg("android-tools"),
    ]}}
