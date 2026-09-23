# Tailscale: LAN の外からもマシン間 SSH とリモートビルドを通す経路
# 用途: 全ホストを tailnet に参加させ、MagicDNS 名（例 `nixos-desktop`）で到達させる。
#       ssh.nix がこの有効化を見て `ssh desktop-ts` 等の接続名を生成する。
# 初回だけ各ホストで `sudo tailscale up` を実行してブラウザで認証する（docs/howtouse/tailscale.md）。
{ ... }: {
  services.tailscale = {
    enable = true;
    # 相手側から直接届く UDP を受けられると、DERP 中継を経由しない直接接続になりやすい。
    openFirewall = true;
  };
}
