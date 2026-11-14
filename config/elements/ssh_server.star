# 手段: この機体で ssh のログインを受け付ける。mDNS で <ホスト名>.local を知らせる。
# どのアカウントに公開鍵を入れるかは accept_ssh_server と accept_ssh_admin が決める。
def config():
    return {"nixos": {
        "services.openssh": {"enable": True, "openFirewall": True, "settings": {"PasswordAuthentication": False, "KbdInteractiveAuthentication": False, "PermitRootLogin": "no"}},
        "services.avahi.publish": {"enable": True, "addresses": True, "domain": True, "workstation": True},
    }}
