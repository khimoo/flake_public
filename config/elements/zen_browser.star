requires = ["gui"]

_PACKAGE = inputPkg("zen-browser", "beta")

def public():
    return {"command": concat(_PACKAGE, "/bin/zen-beta"), "desktop": "zen-beta.desktop"}

def config():
    return {"home": {"home.packages": [_PACKAGE]}}
