# 目的: このホストの設定を管理する。/etc/nixos を管理する利用者の checkout に向け、checkout を pull-repos（private_repos）で更新できるようにする。管理する利用者が purposes で選ぶ。
requires = ["private_repos"]

def user_config(checkout):
    # /etc/nixos 自体を flake の参照にできるよう、flake.nix だけでなく checkout 全体を指す。
    return {"nixos": {"systemd.tmpfiles.rules": ["L+ /etc/nixos - - - - " + checkout.root]}}
