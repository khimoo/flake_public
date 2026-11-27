# 目的: AI 協業掲示板を動かす。Web UI は 127.0.0.1 で待ち、tailnet の端末からは門番（tailnet_gate）を通して
# http://aiboard.home.arpa/ で開く。門番は use_aiboard を選んだホストだけを通す（docs/howtouse/aiboard.md）。
requires = ["expose_services", "hermes_agent", "tailnet_gate"]
needs = ["nixos_system"]
role = True

_PORT = 15280

def user_config(tailnet_web):
    name = tailnet_web.names["serve_aiboard"]
    return {
        "home": {
            "aiboard.server.names": [name],
            "aiboard.server.port": _PORT,
        },
        "home_imports": [repoModule("modules/home-manager/aiboard/default.nix")],
        "nixos": {
            ("services", "caddy", "virtualHosts", "http://" + name + ":" + str(tailnet_web.gate_port)): {
                "extraConfig": tailnet_web.gate["serve_aiboard"] + "reverse_proxy 127.0.0.1:" + str(_PORT) + "\n",
            },
        },
    }
