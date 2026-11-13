# 目的: Quaderno で書いた PDF を手元のアーカイブへ取り込む（docs/howtouse/quaderno.md）。
needs = ["keep_quaderno_archive"]

def writes(quaderno, user, host):
    archive = host.quaderno_archive
    if not archive.startswith("/"):
        fail("quaderno: archive must be an absolute path")
    if archive.startswith("/home/") and not archive.startswith(user.home + "/"):
        fail("quaderno: archive points to another user's home")
    return [write(quaderno, {"pull": {
        "archive": archive,
        "remote_root": getattr(host, "quaderno_remote_root", "Document"),
    }})]

def user_config(user, host):
    return {"nixos": {"systemd.tmpfiles.rules": ["d " + host.quaderno_archive + " 0755 " + user.name + " users -"]}}
