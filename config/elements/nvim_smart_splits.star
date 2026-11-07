# kitty 側の kitten も同じパッケージから置く（gui/kitty.nix）。
def writes(neovim):
    return [write(neovim, {
        "feature": "smart_splits",
        "data": {"smart_splits": {"plugin": concat(pkg("vimPlugins.smart-splits-nvim"))}},
    })]
