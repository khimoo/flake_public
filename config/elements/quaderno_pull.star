# 目的: Quaderno で書いた PDF を手元のアーカイブへ取り込む（docs/howtouse/quaderno.md）。
# 取り込みの記録はマシンごとなので、2台で選ぶと両方が全件を取り込む。1台だけで選ぶ。
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
