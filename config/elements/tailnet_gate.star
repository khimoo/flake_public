# 手段: このホストで動かす Web UI の門番。tailnet の側だけに門番のポートを開け、名前（Host）で Web UI を選び、
# 接続元の端末を tailscale whois で調べて、許した端末だけを 127.0.0.1 の Web UI へ渡す（docs/architecture/tailnet-web.md）。
# Web UI を足すのは serve_* の側で、services.caddy.virtualHosts に http://<名前>:<門番のポート> を書く。
requires = ["tailscale"]

def config(host, tailscale, tailnet_web):
    port = tailnet_web.gate_port
    auth = repoPkg("packages/tailnet-gate")
    return {"nixos": {
        "services.caddy.enable": True,
        "services.caddy.openFirewall": False,
        ("networking", "firewall", "interfaces", tailscale.interface, "allowedTCPPorts"): [port],
        # 名前の合わない要求（IP で直接来たもの、ほかの名前に向け直されたもの）は通さない。
        ("services", "caddy", "virtualHosts", "http://:" + str(port)): {"extraConfig": "respond 403\n"},
        "systemd.services.tailnet-gate-auth": {
            "description": "tailnet の門番: 接続元の端末を調べる",
            "wantedBy": ["multi-user.target"],
            "after": ["tailscaled.service"],
            "serviceConfig": {
                "ExecStart": concat(auth, "/bin/tailnet-gate-auth --listen " + tailnet_web.auth + " --self " + host.hostname + " --tailscale ", exe("tailscale", "tailscale")),
                "DynamicUser": True,
                "Restart": "on-failure",
            },
        },
    }}
