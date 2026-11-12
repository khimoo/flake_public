# /etc/nixos を、このホストを管理する利用者の checkout に向ける。管理する利用者が purposes で選ぶ。
def user_config(checkout):
    # /etc/nixos 自体を flake の参照にできるよう、flake.nix だけでなく checkout 全体を指す。
    return {"nixos": {"systemd.tmpfiles.rules": ["L+ /etc/nixos - - - - " + checkout.root]}}
