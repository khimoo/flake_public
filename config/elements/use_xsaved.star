# 手段: 自分用サーバの xsaved の検索画面を、このホストのブラウザから http://xsaved.home.arpa/ で開く（クライアントの側。docs/howtouse/xsaved.md）。
# 名前は自分自身へ向け、手元の Caddy が xsaved を動かすホストの門番へ渡す。門番は use_xsaved を選んだホストだけを通す。
requires = ["find_home_server"]
needs = ["nixos_system"]
role = True

def user_config(find_home_server, tailnet_web):
    if "serve_xsaved" not in find_home_server.services:
        fail("use_xsaved: no server runs serve_xsaved")
    name = tailnet_web.names["serve_xsaved"]
    server = find_home_server.services["serve_xsaved"]["host"]
    return {"nixos": {
        ("networking", "hosts", "127.0.0.1"): [name],
        ("networking", "hosts", "::1"): [name],
        "services.caddy.enable": True,
        "services.caddy.openFirewall": False,
        ("services", "caddy", "virtualHosts", "http://" + name): {
            "listenAddresses": ["127.0.0.1", "[::1]"],
            "extraConfig": "reverse_proxy " + server + ":" + str(tailnet_web.gate_port) + "\n",
        },
    }}
