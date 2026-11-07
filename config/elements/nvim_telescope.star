def writes(neovim):
    return [write(neovim, {"feature": "telescope", "packages": [pkg("ripgrep")]})]
