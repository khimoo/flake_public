# 目的: 自分用サーバとして、GNOME の画面を RDP で公開する。tailnet の側の 3389〜3399 番だけを開ける（docs/howtouse/tailscale.md）。
role = True

def config(tailscale):
    return {"nixos": {
        ("networking", "firewall", "interfaces", tailscale.interface, "allowedTCPPortRanges"): [{"from": 3389, "to": 3399}],
        # linked 状態では GNOME 設定が RDP の項目を隠すため、ユニットを enabled にする。
        "systemd.services.gnome-remote-desktop.wantedBy": ["graphical.target"],
    }}
