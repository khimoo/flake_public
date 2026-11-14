# 手段: この機体の Nix のビルドを、自分用サーバ（serve_builds）に任せる（クライアントの側）。
requires = ["find_home_server", "tailscale"]

# 同時に何ジョブ送るか。上限は任せる先の機体が自分の max-jobs でかけるので、ここでは多めに送る。
_MAX_JOBS = 32
# 自分用サーバが引き受けられるビルドの種類。kvm は「自分用サーバは KVM を持つ」という前提（docs/architecture/confgen.md の「今後の課題」）。
_FEATURES = ["benchmark", "big-parallel", "kvm", "nixos-test"]

def config(host, find_home_server):
    if find_home_server.host == host.hostname:
        fail("remote_build: this host is the home server")
    result = {
        "nix.distributedBuilds": True,
        "nix.settings.builders-use-substitutes": True,
    }
    if not getattr(host, "local_builds", True):
        result["nix.settings.max-jobs"] = 0
    return {"nixos": result}

def user_config(user, machines, find_home_server, lan_ssh_key):
    return {"nixos": {
        "nix.buildMachines": [{
            "hostName": find_home_server.services["serve_builds"]["tailnet"],
            "protocol": "ssh-ng",
            "system": machines.all[find_home_server.host]["system"],
            "maxJobs": _MAX_JOBS,
            "supportedFeatures": _FEATURES,
            # nix-daemon は root で動き、root の ~/.ssh には共有鍵がないので、この利用者の鍵を絶対パスで渡す。
            "sshKey": lan_ssh_key.path,
        }],
        # --build-host で取り戻す成果物も、自分用サーバから --target-host で送られてくるシステムも、署名がない。
        # nix-copy-closure は利用者として取り込むので、利用者を信頼しないと取り込みを拒否される。
        "nix.settings.trusted-users": [user.name],
    }}
