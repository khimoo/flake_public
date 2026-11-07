# 目的: sshfs で別の PC のファイルを編集する。
# sshfs 上の文書だけ、tinymist の PDF を手元の tmpfs に出す判定に使う値を Neovim に渡す。
def writes(neovim, util_linux):
    return [write(neovim, {"tinymist_output": {
        "findmnt": util_linux.findmnt,
        "fs_type": "fuse.sshfs",
    }})]

def config():
    return {"home": {"home.packages": [pkg("sshfs")]}}
