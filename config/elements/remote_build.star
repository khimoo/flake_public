# 手段: この機体の Nix のビルドを、自分用サーバ（serve_builds）に任せる（クライアントの側）。
requires = ["find_home_server", "tailscale", "lan_ssh_key"]

# 同時に何ジョブ送るか。上限は任せる先の機体が自分の max-jobs でかけるので、ここでは多めに送る。
_MAX_JOBS = 32
# 自分用サーバが引き受けられるビルドの種類。kvm は「自分用サーバは KVM を持つ」という前提（docs/architecture/confgen.md の「今後の課題」）。
_FEATURES = ["benchmark", "big-parallel", "kvm", "nixos-test"]

def config(host, machines, find_home_server):
    server = find_home_server.host
    if server == host.hostname:
        fail("remote_build: this host is the home server")
    machine = machines.all[server]
    result = {
        "nix.distributedBuilds": True,
        "nix.buildMachines": [{
            "hostName": find_home_server.services["serve_builds"]["tailnet"],
            "protocol": "ssh-ng",
            "system": machine["system"],
            "maxJobs": _MAX_JOBS,
            "supportedFeatures": _FEATURES,
            # nix-daemon は root で動き、root の ~/.ssh には共有鍵がない。
            "sshKey": "/home/" + host.users[0]["name"] + "/.ssh/id_lan",
        }],
        "nix.settings.builders-use-substitutes": True,
    }
    if not getattr(host, "local_builds", True):
        result["nix.settings.max-jobs"] = 0
    return {"nixos": result}

# --build-host で取り戻す成果物も、自分用サーバから --target-host で送られてくるシステムも、署名がない。
# nix-copy-closure は利用者として取り込むので、利用者を信頼しないと取り込みを拒否される。
def user_config(user):
    return {"nixos": {"nix.settings.trusted-users": [user.name]}}
