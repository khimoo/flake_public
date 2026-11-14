# 手段: xsaved の Web UI を、自分用サーバのブラウザで名前（利用者の表の proxy_name）で開けるようにする。
def user_config(serve_xsaved):
    name = serve_xsaved.values["proxy_name"]
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
