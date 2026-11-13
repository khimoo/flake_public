_LAN_PUBLIC_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMsQXfS2j/9NtGDBz7EAP4I3DamWH1I6cromNqWOZ2pb pomu@lan"

def _short(name):
    return name[len("nixos-"):] if name.startswith("nixos-") else name

def _block(user, patterns, hostname):
    return "Host %s\n  HostName %s\n  User %s\n  IdentityFile ~/.ssh/id_lan\n  StrictHostKeyChecking accept-new\n  ConnectTimeout 10\n" % (patterns, hostname, user)

def public(machines):
    # クライアントが自分用サーバへ接続するときの、LAN（Host <短い名前>）と tailnet 越し（Host <短い名前>-ts）の接続名。
    return {
        "lan": {name: _short(name) for name in machines.all if "ssh_user" in machines.all[name]},
        "tailnet": {name: _short(name) + "-ts" for name in machines.all if "ssh_user" in machines.all[name]},
    }

def config(host, machines, incoming):
    tailnet = len(incoming) > 0
    blocks = []
    for name in sorted(machines.all):
        machine = machines.all[name]
        if "ssh_user" not in machine:
            continue
        blocks.append(_block(machine["ssh_user"], "%s %s %s.local" % (_short(name), name, name), name + ".local"))
        if tailnet:
            blocks.append(_block(machine["ssh_user"], _short(name) + "-ts", name))
    blocks.append("Host github.com\n  User git\n  IdentityFile ~/.ssh/id_github\n")
    return {"nixos": {
        "services.openssh": {"enable": True, "openFirewall": True, "settings": {"PasswordAuthentication": False, "KbdInteractiveAuthentication": False, "PermitRootLogin": "no"}},
        ("users", "users", host.users[0]["name"], "openssh", "authorizedKeys", "keys"): [_LAN_PUBLIC_KEY],
        "programs.ssh.extraConfig": "".join(blocks),
        "services.avahi.publish": {"enable": True, "addresses": True, "domain": True, "workstation": True},
    }}
