# 手段: 自分用サーバの Web UI を、決まった名前（<サービス>.home.arpa）で tailnet の端末に届ける約束ごと。
# 端末のブラウザは自分自身（127.0.0.1）の Caddy に名前で接続し、その Caddy がサーバの門番（tailnet_gate）へ渡す。
# 門番は接続元の端末を tailscale whois で調べ、use_* を選んだホストだけを通す（docs/architecture/tailnet-web.md）。
# サーバの側と端末の側が同じ値を使うので、ここにまとめて置く。値だけを持ち、設定は出さない。
_GATE_PORT = 8780
_AUTH = "127.0.0.1:8781"
# serve_* と、それを使う端末が選ぶ use_*、ブラウザで開く名前。
_SERVICES = {
    "serve_aiboard": ("use_aiboard", "aiboard.home.arpa"),
    "serve_xsaved": ("use_xsaved", "xsaved.home.arpa"),
}

def public(roles):
    names = {}
    gate = {}
    for service, (use, name) in _SERVICES.items():
        devices = sorted([host for host in roles.hosts if any([use in chosen for chosen in roles.hosts[host].values()])])
        names[service] = name
        # 門番の Caddy のサイトに書く、接続元の確かめ方。header_up は、端末が同じ名前の見出しを送ってきても上書きする。
        gate[service] = "forward_auth " + _AUTH + " {\n\turi /check?allow=" + ",".join(devices) + "\n\theader_up X-Tailnet-Peer {remote_host}\n}\n"
    return {"gate_port": _GATE_PORT, "auth": _AUTH, "names": names, "gate": gate}
