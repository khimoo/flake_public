# 手段: xsaved の Web UI を、自分用サーバのブラウザで名前（<アカウント名>.xsaved.localhost）で開けるようにする。
def user_config(user, serve_xsaved):
    name = user.name + ".xsaved.localhost"
    return {"nixos": {
        ("networking", "hosts", "127.0.0.1"): [name],
        ("networking", "hosts", "::1"): [name],
        "services.caddy.enable": True,
        "services.caddy.openFirewall": False,
        ("services", "caddy", "virtualHosts", "http://" + name): {
            "listenAddresses": ["127.0.0.1", "[::1]"],
            "extraConfig": "reverse_proxy 127.0.0.1:" + str(serve_xsaved.web_port) + "\n",
        },
    }}
