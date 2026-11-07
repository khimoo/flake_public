def writes(neovim):
    return [write(neovim, {
        "feature": "dap",
        "data": {"dap": {"python": exe("python-debugpy", "python")}},
    })]
