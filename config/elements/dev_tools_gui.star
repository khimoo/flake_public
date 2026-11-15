requires = ["gui"]

def user_config():
    return {"home": {"home.packages": [
        pkg("jetbrains.idea"),
        pkg("android-tools"),
    ]}}
