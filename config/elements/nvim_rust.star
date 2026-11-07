def writes(neovim):
    return [write(neovim, {
        "feature": "rust",
        "data": {"rust": {"codelldb": concat(
            pkg("vscode-extensions.vadimcn.vscode-lldb"),
            "/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb",
        )}},
    })]
