# 手段: 自分用サーバの Quaderno のアーカイブを使う。Quaderno で書いた PDF を、ssh でアーカイブへ送って取り込む（クライアントの側。docs/howtouse/quaderno.md）。
# 接続先は利用者の値 home_server。
needs = ["machine_ssh", "tailscale"]
requires = ["lan_ssh_key"]

def writes(quaderno, user, host, machine_ssh):
    server = user.home_server
    if server not in machine_ssh.tailnet:
        fail("quaderno: home_server " + server + " is not a host with ssh_user")
    return [write(quaderno, {"pull": {
        "ssh": machine_ssh.tailnet[server],
        "remote_root": getattr(host, "quaderno_remote_root", "Document"),
    }})]
