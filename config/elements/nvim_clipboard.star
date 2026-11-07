def writes(neovim, host):
    packages = [pkg("xclip"), pkg("wl-clipboard")] if host.linux else []
    return [write(neovim, {"feature": "clipboard", "packages": packages})]
