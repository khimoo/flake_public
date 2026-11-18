# 手段: このホストの Nix のビルドを、自分用サーバ（serve_builds）に任せる（クライアントの側）。
requires = ["find_home_server", "tailscale"]

# 同時に何ジョブ送るか。上限は任せる先のホストが自分の max-jobs でかけるので、ここでは多めに送る。
_MAX_JOBS = 32
_BASE_FEATURES = ["benchmark", "big-parallel"]
# kvm と nixos-test は、任せる先のホストが serve_kvm_builds（needs = ["local_kvm"]）を持つときだけ載せる。
_KVM_FEATURES = ["kvm", "nixos-test"]

def _builder(find_home_server):
    if "serve_builds" not in find_home_server.services:
        fail("remote_build: no server runs serve_builds")
    return find_home_server.services["serve_builds"]

def config(host, find_home_server):
    builder = _builder(find_home_server)
    if builder["host"] == host.hostname:
        fail("remote_build: this host is the home server")
    result = {
        "nix.distributedBuilds": True,
        "nix.settings.builders-use-substitutes": True,
    }
    if not getattr(host, "local_builds", True):
        result["nix.settings.max-jobs"] = 0
    return {"nixos": result}

def user_config(user, machines, find_home_server, lan_ssh_key):
    builder = _builder(find_home_server)
    target_host = builder["host"]
    kvm = find_home_server.services.get("serve_kvm_builds")
    features = _BASE_FEATURES + (_KVM_FEATURES if kvm != None and kvm["host"] == target_host else [])
    return {"nixos": {
        "nix.buildMachines": [{
            "hostName": builder["tailnet"],
            "protocol": "ssh-ng",
            "system": machines.all[target_host]["system"],
            "maxJobs": _MAX_JOBS,
            "supportedFeatures": features,
            # nix-daemon は root で動き、root の ~/.ssh には共有鍵がないので、このユーザーの鍵を絶対パスで渡す。
            "sshKey": lan_ssh_key.path,
        }],
        # --build-host で取り戻す成果物も、自分用サーバから --target-host で送られてくるシステムも、署名がない。
        # nix-copy-closure はユーザーとして取り込むので、ユーザーを信頼しないと取り込みを拒否される。
        "nix.settings.trusted-users": [user.name],
    }}
