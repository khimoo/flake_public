requires = ["direnv"]

def writes(neovim):
    return [write(neovim, {
        "feature": "direnv",
        "packages": [pkg("direnv")],
    })]
