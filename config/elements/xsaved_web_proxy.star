# 手段: xsaved の Web UI を、自分用サーバのブラウザで名前（ホストのファイルの xsaved_proxy の name）で開けるようにする。
def config(host, serve_xsaved):
    proxy = host.xsaved_proxy
    port = serve_xsaved.users[proxy["user"]].get("web_port", 8765)
    return {"nixos": {
        ("networking", "hosts", "127.0.0.1"): [proxy["name"]],
        ("networking", "hosts", "::1"): [proxy["name"]],
        "services.caddy.enable": True,
        "services.caddy.openFirewall": False,
        ("services", "caddy", "virtualHosts", "http://" + proxy["name"]): {
            "listenAddresses": ["127.0.0.1", "[::1]"],
            "extraConfig": "reverse_proxy 127.0.0.1:" + str(port) + "\n",
        },
    }}
