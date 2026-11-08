def _home_path(user, path):
    if path.startswith("/") or ".." in path.split("/"):
        fail("personal_files: destinations must live below the user's home")
    return user.home + "/" + path

def writes(user, host, private_repos, secrets):
    result = []
    for repo in getattr(host, "private_repos", []):
        result.append(write(private_repos, {"url": repo["url"], "dest": _home_path(user, repo["dest"])}))
        result.append(write(secrets, private_repos.github_secret))
    destinations = {}
    for item in getattr(user, "secrets", []) + getattr(host, "secrets", []):
        path = _home_path(user, item["path"])
        if path in destinations:
            fail("personal_files: duplicate secret destination")
        destinations[path] = True
        result.append(write(secrets, {"secret": item["secret"], "path": path, "mode": item.get("mode", "600")}))
    lan = getattr(host, "lan_ssh", False) or getattr(user, "lan_ssh", False)
    names = {}
    for key in getattr(user, "ssh_keys", []):
        name = key["name"]
        first_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
        if not name or name[0] not in first_chars or any([name[i] not in first_chars + ".-" for i in range(len(name))]):
            fail("personal_files: invalid SSH key filename")
        if name in names or (lan and name == "id_lan"):
            fail("personal_files: duplicate SSH key filename")
        names[name] = True
        result.append(write(secrets, {"secret": key["secret"], "path": user.home + "/.ssh/" + name, "mode": "600", "ssh_key": True}))
    if lan:
        result.append(write(secrets, {"secret": "lan_ssh_key", "path": user.home + "/.ssh/id_lan", "mode": "600"}))
    return result
