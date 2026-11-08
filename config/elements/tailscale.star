# LAN の外からもマシン間 SSH とリモートビルドを通す経路。全ホストを tailnet に参加させ、MagicDNS 名
# （例 nixos-desktop）で到達させる。初回だけ各ホストで `sudo tailscale up` を実行してブラウザで認証する
# （docs/howtouse/tailscale.md）。
def public():
    return {"interface": "tailscale0"}

def config():
    return {"nixos": {
        "services.tailscale.enable": True,
        # 相手側から直接届く UDP を受けられると、DERP 中継を経由しない直接接続になりやすい。
        "services.tailscale.openFirewall": True,
    }}
