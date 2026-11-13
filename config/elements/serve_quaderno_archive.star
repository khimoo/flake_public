# 目的: Quaderno の文書を受け取るアーカイブと、取り込みの記録を持つ（サーバの側。docs/architecture/quaderno.md）。
# 記録をサーバの1か所に置くので、どの機体のクライアントが Quaderno を見つけても、同じ改訂を二度取り込まない。
needs = ["machine_ssh"]

def user_config(user, host):
    archive = host.quaderno_archive
    if not archive.startswith("/"):
        fail("quaderno: archive must be an absolute path")
    if archive.startswith("/home/") and not archive.startswith(user.home + "/"):
        fail("quaderno: archive points to another user's home")
    receive = shellAppEnv("quaderno-archive", [pkg("python3")], {
        "QUADERNO_ARCHIVE_DIR": archive,
        "QUADERNO_STATE_FILE": user.home + "/.local/state/quaderno/state.json",
    }, concat("exec python3 ", repoPath("modules/home-manager/quaderno_archive.py"), ' "$@"\n'))
    return {
        "home": {"home.packages": [receive]},
        "nixos": {"systemd.tmpfiles.rules": ["d " + archive + " 0755 " + user.name + " users -"]},
    }
