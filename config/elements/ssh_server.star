# 手段: このホストで ssh のログインを受け付ける。mDNS で <ホスト名>.local を知らせる。
# 公開鍵を入れるのは持ち主のアカウント（personal_files）。
role = True
def config():
    return {"nixos": {
        "services.openssh": {"enable": True, "openFirewall": True, "settings": {"PasswordAuthentication": False, "KbdInteractiveAuthentication": False, "PermitRootLogin": "no"}},
        "services.avahi.publish": {"enable": True, "addresses": True, "domain": True, "workstation": True},
    }}
