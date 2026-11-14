# 手段: 自分用サーバへ ssh で接続する。接続先（サーバと、各サービスを動かすアカウント）を求め、鍵（lan_ssh_key）を置く。
# クライアントの要素は、この要素だけを requires に挙げる。
# 自分用サーバは、run_home_server が真のアカウントがいるただ 1 つのホスト（roles）。ホストのファイルや持ち主の値には書かない。
needs = ["tailscale"]
requires = ["lan_ssh_key"]

def public(roles, connect_ssh):
    servers = [name for name in sorted(roles.hosts) if any(["run_home_server" in names for names in roles.hosts[name].values()])]
    if len(servers) != 1:
        fail("find_home_server: exactly one host must have a user with run_home_server, found " + (", ".join(servers) or "none"))
    host = servers[0]
    services = {}
    for user, names in roles.hosts[host].items():
        for name in names:
            if not name.startswith("serve_"):
                continue
            if "accept_ssh_server" not in names:
                fail("find_home_server: user " + user + " of " + host + " runs " + name + " but does not accept ssh logins (accept_ssh_server needs ssh_server and run_home_server)")
            if name in services:
                fail("find_home_server: more than one user of " + host + " runs " + name)
            # Host ブロックのログイン名と同じアカウントなら、接続名だけで足りる。
            prefix = "" if connect_ssh.login[host] == user else user + "@"
            services[name] = {"account": user, "lan": prefix + connect_ssh.lan[host], "tailnet": prefix + connect_ssh.tailnet[host]}
    # services[<serve_* の要素名>] は、サービスを動かすアカウントと、ssh に渡す接続先（LAN と tailnet 越し）。
    return {"host": host, "services": services}
