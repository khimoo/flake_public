# Quaderno で書いた PDF を、自分用サーバのアーカイブへ ssh で送って取り込む（クライアントの側。docs/howtouse/quaderno.md）。
# Quaderno を使う機体（quaderno が入る機体）のうち、自宅のマシンへ ssh で接続できる機体でだけ入る。接続先は利用者の値 home_server。
when = ["quaderno", "machine_ssh", "tailscale"]

def writes(quaderno, user, host, machine_ssh):
    server = user.home_server
    if server not in machine_ssh.tailnet:
        fail("quaderno: home_server " + server + " is not a host with ssh_user")
    return [write(quaderno, {"pull": {
        "ssh": machine_ssh.tailnet[server],
        "remote_root": getattr(host, "quaderno_remote_root", "Document"),
    }})]
