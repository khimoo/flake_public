# sshfs 上の文書だけ、tinymist の PDF を手元の tmpfs に出す判定に使う値を Neovim に渡す。
# 値を読むのは nvim_lsp が有効にする Lua なので、LSP の無いホストでは作らない。
when = ["sshfs_editing", "nvim_lsp"]

def writes(neovim, util_linux):
    return [write(neovim, {"data": {"lsp": {"tinymistOutput": {
        "findmnt": util_linux.findmnt,
        "fsType": "fuse.sshfs",
    }}}})]
