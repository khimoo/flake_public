# 目的: 自分用サーバの AI 協業掲示板を、このホストのブラウザから http://aiboard.home.arpa/ で開く（docs/howtouse/aiboard.md）。
# 名前は自分自身へ向け、手元の Caddy が掲示板を動かすホストの門番へ渡す。門番は use_aiboard を選んだホストだけを通す。
requires = ["find_home_server"]
needs = ["nixos_system"]
role = True

def user_config(find_home_server, tailnet_web):
    if "serve_aiboard" not in find_home_server.services:
        fail("use_aiboard: no server runs serve_aiboard")
    name = tailnet_web.names["serve_aiboard"]
    server = find_home_server.services["serve_aiboard"]["host"]
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
