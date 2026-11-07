def writes(neovim):
    return [write(neovim, {"feature": "typst_preview", "packages": [pkg("tinymist"), pkg("websocat")]})]
