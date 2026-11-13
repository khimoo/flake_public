# 担当: 会社の機体として、自宅のマシンへの接続経路を持たない（docs/architecture/wsl.md）。
kind = "machine_role"
conflicts = ["machine_ssh", "tailscale", "remote_build", "remote_workspace"]
