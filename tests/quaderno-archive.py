"""自分用サーバのアーカイブ（quaderno-archive）と、ssh で呼ぶクライアント（SshArchive）が期待どおりか。

ssh の代わりに、最後の引数（リモートで実行するコマンド）を手元の sh で実行するスクリプトを使う。
"""
import os
import stat
import sys
import tempfile
from pathlib import Path

from quaderno_archive import ArchiveRefused, ServerUnreachable, SshArchive

work = Path(tempfile.mkdtemp())
archive = work / "archive"
state = work / "state" / "state.json"
bin_dir = work / "bin"
bin_dir.mkdir()


def script(name, text):
    path = bin_dir / name
    path.write_text("#!/bin/sh\n" + text)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return str(path)


script("quaderno-archive", 'exec "{}" "{}" "$@"\n'.format(sys.executable, Path("quaderno_archive.py").resolve()))
fake_ssh = script("fake-ssh", 'for last; do :; done\nexec sh -c "$last"\n')
down_ssh = script("down-ssh", "echo 'ssh: connect to host desktop-ts port 22: No route to host' >&2\nexit 255\n")
os.environ.update(PATH=str(bin_dir) + ":" + os.environ["PATH"], QUADERNO_ARCHIVE_DIR=str(archive), QUADERNO_STATE_FILE=str(state))

server = SshArchive("desktop-ts", ssh=[fake_ssh])
entry = {"entry_id": "1", "file_revision": "r1", "entry_path": "Document/ノート 1.pdf"}

# 記録が無ければ空として返す。
assert server.state() == {}

# 受け取った中身をアーカイブの同じ相対パスに置き、記録を更新する。空白や日本語の名前もそのまま通る。
assert server.store(entry, b"%PDF-1") is True
assert (archive / "Document" / "ノート 1.pdf").read_bytes() == b"%PDF-1"
assert server.state() == {"1": "r1"}

# 別の機体が同じ改訂を送っても、置き直さずに記録済みと答える。
assert server.store(entry, b"%PDF-1") is False

# 改訂が変われば置き直す。
assert server.store(dict(entry, file_revision="r2"), b"%PDF-22") is True
assert (archive / "Document" / "ノート 1.pdf").read_bytes() == b"%PDF-22"
assert server.state() == {"1": "r2"}

# アーカイブの外を指すパスは断り、何も書かない。
for path in ["../escape.pdf", "/etc/passwd", "Document/../../escape.pdf"]:
    try:
        server.store(dict(entry, entry_id="2", entry_path=path), b"x")
    except ArchiveRefused:
        pass
    else:
        raise AssertionError("accepted " + path)
assert not (work / "escape.pdf").exists()
assert server.state() == {"1": "r2"}

# ssh が接続に失敗したら、サーバに届かないことをクライアントに知らせる（受け取りを断ったのとは区別する）。
try:
    SshArchive("desktop-ts", ssh=[down_ssh]).state()
except ServerUnreachable as e:
    assert "No route to host" in str(e)
else:
    raise AssertionError("unreachable server was not reported")

# 書き込みの途中の一時ファイルを残さない。
assert not list(archive.rglob("*.part"))
print("quaderno archive tests passed")
