# 目的: 自分用サーバとして、Niri の画面を Sunshine で配信する。tailnet の側の Sunshine のポートだけを開ける（docs/howtouse/tailscale.md）。
requires = ["expose_services", "sunshine_virtual_output", "niri_remote_session"]
role = True

def config(tailscale, sunshine):
    interface = ("networking", "firewall", "interfaces", tailscale.interface)
    return {"nixos": {
        interface + ("allowedTCPPorts",): sunshine.tcp_ports,
        interface + ("allowedUDPPorts",): sunshine.udp_ports,
    }}

def user_config():
    # sunshine.service は NixOS のユーザーユニットで、全ユーザーに見える。このアカウントのセッションだけで起動するよう、wants を個別に張る。
    return {"home": {
        ("xdg", "configFile", "systemd/user/graphical-session.target.wants/sunshine.service", "source"): outOfStoreLink("/etc/systemd/user/sunshine.service"),
    }}
