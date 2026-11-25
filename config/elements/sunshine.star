# 手段: Moonlight へ画面を配信する Sunshine。起動とファイアウォールの許可はこのコンポーネントでは行わず、配信するアカウントの側（serve_remote_desktop）が決める。
# Web UI の TCP 47990 は公開する組に入れない。ペアリングは ssh のポート転送で開く（docs/howtouse/tailscale.md）。
requires = ["niri"]
needs = ["nixos_system"]

def public():
    return {
        "package": pkg("sunshine"),
        "tcp_ports": [47984, 47989, 48010],
        "udp_ports": [47998, 47999, 48000, 48002, 48010],
    }

def accept(app = None):
    if app == None:
        fail("sunshine: app is required")
    return app

def config(incoming):
    return {"nixos": {
        "services.sunshine.enable": True,
        # NixOS のモジュールは autoStart と openFirewall をホスト全体に適用する。ここでは外し、利用するアカウントとインターフェースを別に決める。
        "services.sunshine.autoStart": False,
        "services.sunshine.openFirewall": False,
        # 仮想出力は DRM の出力ではないので、KMS ではなく wlr-screencopy で取る。
        "services.sunshine.capSysAdmin": False,
        "services.sunshine.settings": {"capture": "wlr"},
        "services.sunshine.applications": {"apps": [w.value for w in incoming]},
    }}
