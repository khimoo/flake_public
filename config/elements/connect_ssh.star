# 手段: ほかの機体へ ssh で接続するための Host ブロックを書く。接続先は、ssh のログインを受け付けるアカウント
# （accept_ssh_admin か accept_ssh_server が真のアカウント）がいるホスト。roles から求めるので、ホストのファイルには書かない。
# 鍵のファイル名。置くのは lan_ssh_key で、この名前を公開値から読む。
_IDENTITY_FILE = ".ssh/id_lan"

def _short(name):
    return name[len("nixos-"):] if name.startswith("nixos-") else name

def _block(user, patterns, hostname):
    return "Host %s\n  HostName %s\n  User %s\n  IdentityFile ~/%s\n  StrictHostKeyChecking accept-new\n  ConnectTimeout 10\n" % (patterns, hostname, user, _IDENTITY_FILE)

# ホストごとのログイン名。管理するアカウントがいればそのアカウント、いなければ自分用サーバを動かすアカウント。
def _logins(roles):
    logins = {}
    for name in sorted(roles.hosts):
        for role in ["accept_ssh_admin", "accept_ssh_server"]:
            accounts = [user for user, names in roles.hosts[name].items() if role in names]
            if len(accounts) > 1:
                fail("connect_ssh: host " + name + " has more than one user with " + role + ": " + ", ".join(accounts))
            if accounts and name not in logins:
                logins[name] = accounts[0]
    return logins

def public(roles):
    logins = _logins(roles)
    # LAN（Host <短い名前>）と tailnet 越し（Host <短い名前>-ts）の接続名。
    return {
        "identity_file": _IDENTITY_FILE,
        "login": logins,
        "lan": {name: _short(name) for name in logins},
        "tailnet": {name: _short(name) + "-ts" for name in logins},
    }

def config(roles, incoming):
    tailnet = len(incoming) > 0
    blocks = []
    for name, user in _logins(roles).items():
        blocks.append(_block(user, "%s %s %s.local" % (_short(name), name, name), name + ".local"))
        if tailnet:
            blocks.append(_block(user, _short(name) + "-ts", name))
    return {"nixos": {"programs.ssh.extraConfig": "".join(blocks)}}
