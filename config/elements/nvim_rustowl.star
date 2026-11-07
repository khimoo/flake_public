# RustOwl と対応する Neovim のプラグインは、同じ固定した flake から取る（overlays/neovim-tools.nix）。
# 配布が x86_64-linux だけなので、ほかでは機能ごと入れない。
def writes(neovim, host):
    if host.system != "x86_64-linux":
        return []
    return [write(neovim, {
        "feature": "rustowl",
        "data": {"rustowl": {
            "command": exe("rustowl-locked", "rustowl"),
            "plugin": concat(pkg("rustowl-nvim-locked")),
        }},
    })]
