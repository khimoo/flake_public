requires = ["machine_ssh", "tailscale"]

def config(host, machines):
    builders = []
    for name in sorted(machines.all):
        machine = machines.all[name]
        if name == host.hostname or "builder" not in machine:
            continue
        short = name[len("nixos-"):] if name.startswith("nixos-") else name
        builders.append({
            "hostName": short + "-ts",
            "protocol": "ssh-ng",
            "system": machine["system"],
            "maxJobs": machine["builder"]["max_jobs"],
            "supportedFeatures": machine["builder"]["supported_features"],
            # nix-daemon は root で動き、root の ~/.ssh には共有鍵がない。
            "sshKey": "/home/" + host.users[0]["name"] + "/.ssh/id_lan",
        })
    if not builders:
        fail("remote_build: no other host has a builder in config/hosts/*.toml")
    result = {"nix.distributedBuilds": True, "nix.buildMachines": builders, "nix.settings.builders-use-substitutes": True}
    if not getattr(host, "local_builds", True):
        result["nix.settings.max-jobs"] = 0
    return {"nixos": result}
