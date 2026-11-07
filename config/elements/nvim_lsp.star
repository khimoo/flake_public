# サーバー名は lua/features/lsp.lua が vim.lsp.enable に渡す。
_SERVERS = [
    ("pyright", "pyright"),
    ("lua-language-server", "lua_ls"),
    ("nil", "nil_ls"),
    ("tinymist", "tinymist"),
    ("marksman", "marksman"),
]

def writes(neovim):
    return [write(neovim, {
        "feature": "lsp",
        "packages": [pkg(p) for p, _ in _SERVERS] + [pkg("nixfmt")],
        "data": {"lsp": {"servers": [s for _, s in _SERVERS]}},
    })]
