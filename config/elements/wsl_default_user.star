# WSL が既定でログインするアカウントは、このホストを管理するアカウント（etc_nixos_link を選んだアカウント）。
def config(roles, host):
    admins = [user for user, names in roles.hosts.get(host.hostname, {}).items() if "etc_nixos_link" in names]
    if len(admins) != 1:
        fail("wsl_default_user: host " + host.hostname + " needs exactly one user with etc_nixos_link, found " + (", ".join(admins) or "none"))
    return {"nixos": {"wsl.defaultUser": admins[0]}}
