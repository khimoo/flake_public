# 手段: 自分用サーバへ ssh で接続する。サービス（serve_*）ごとに、それを提供するホストとアカウントを roles から求め、鍵（lan_ssh_key）を置く。
# クライアントのコンポーネントは、このコンポーネントだけを requires に挙げる。
# サービスを公開するのは expose_services が有効なアカウント。
# クライアントは services の tailnet の接続名（desktop-ts、gce-ts など）で ssh する。この名前を解決できるのは
# connect_ssh_tailnet が書く Host ブロックだけなので、tailscale だけでは足りない。
requires = ["lan_ssh_key", "connect_ssh_tailnet"]

def public(roles, connect_ssh):
    servers = [name for name in sorted(roles.hosts) if any(["expose_services" in names for names in roles.hosts[name].values()])]
    if not servers:
        fail("find_home_server: no host has a user with expose_services")
    services = {}
    for host in servers:
        for user, names in roles.hosts[host].items():
            if "expose_services" not in names:
                continue
            for name in names:
                if not name.startswith("serve_"):
                    continue
                if name in services:
                    fail("find_home_server: more than one server runs " + name + " (" + services[name]["host"] + "/" + services[name]["account"] + " and " + host + "/" + user + ")")
                services[name] = {
                    "host": host,
                    "account": user,
                    "lan": connect_ssh.lan[host],
                    "tailnet": connect_ssh.tailnet[host],
                }
    # services[<serve_* のコンポーネント名>] は、サービスを動かすホスト、アカウント、ssh に渡す接続先（LAN と tailnet 越し）。
    return {"services": services}
