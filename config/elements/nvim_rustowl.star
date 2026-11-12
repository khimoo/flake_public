# RustOwl と対応する Neovim のプラグインは、同じ固定した flake から取る（overlays/neovim-tools.nix）。
# 配布が x86_64-linux だけなので、x86_64 の Linux の機体でだけ入れる。
when = ["daily_editing", "x86_64_linux"]

def writes(neovim):
    return [write(neovim, {
        "feature": "rustowl",
        "data": {"rustowl": {
            "command": exe("rustowl-locked", "rustowl"),
            "plugin": concat(pkg("rustowl-nvim-locked")),
        }},
    })]
