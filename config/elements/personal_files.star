def writes(user, host, private_repos, secrets):
    result = []
    for repo in getattr(host, "private_repos", []):
        result.append(write(private_repos, {"url": repo["url"], "dest": user.home + "/" + repo["dest"]}))
        result.append(write(secrets, private_repos.github_secret))
    for item in getattr(user, "secrets", []) + getattr(host, "secrets", []):
        result.append(write(secrets, {"secret": item["secret"], "path": user.home + "/" + item["path"], "mode": item.get("mode", "600")}))
    if getattr(host, "lan_ssh", False) or getattr(user, "lan_ssh", False):
        result.append(write(secrets, {"secret": "lan_ssh_key", "path": user.home + "/.ssh/id_lan", "mode": "600"}))
    return result

def config(host, user):
    return {"home": {"local.profile.lanSsh": getattr(host, "lan_ssh", False) or getattr(user, "lan_ssh", False)}}
