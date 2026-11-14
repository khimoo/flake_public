# 手段: GitHub への ssh に GitHub 用の鍵（~/.ssh/id_github）を使う。鍵を置く要素が requires に挙げる。
def config():
    return {"nixos": {"programs.ssh.extraConfig": "Host github.com\n  User git\n  IdentityFile ~/.ssh/id_github\n"}}
