# 目的: Google Compute Engine 上のヘッドレス NixOS VM（ssh と tailnet で接続し、ビルドやサービスを引き受ける）。
kind = "machine"
requires = ["x86_64_linux", "nixos_system", "machine_base", "ssh_server", "connect_ssh", "tailscale", "connect_ssh_tailnet"]

def config():
    return {"nixos_imports": [repoModule("hosts/nixos-gce/hardware.nix")]}
