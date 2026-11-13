"""Quaderno の文書を受け取ってアーカイブに置き、取り込みの記録を持つ（自分用サーバの側）。

各機体の quaderno_transfer.py が ssh でこのコマンドを呼ぶ。記録をサーバの1か所に置くので、
どの機体が Quaderno を見つけても、取り込み済みの改訂を二度取り込まない。

  quaderno-archive state
      記録（entry_id から file_revision への対応）を JSON で標準出力に出す。
  quaderno-archive store ENTRY_ID REVISION SIZE ENTRY_PATH
      標準入力の SIZE バイトを、アーカイブの ENTRY_PATH に置き、記録を更新する。
      同じ改訂がすでに記録されていれば、書かずに終わる。

クライアントの側（SshArchive）もこのファイルに置き、呼び出しの形を1か所で決める。
設計判断は docs/architecture/quaderno.md にある。
"""
import fcntl
import json
import os
import shlex
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path, PurePosixPath


class ServerUnreachable(Exception):
    """自分用サーバに ssh で接続できない。"""


class ArchiveRefused(Exception):
    """自分用サーバの quaderno-archive が受け取りを断った。"""


class SshArchive:
    """自分用サーバの quaderno-archive を ssh で呼ぶ（クライアントの側）。"""

    # ssh は接続や認証に失敗すると 255 で終わる。リモートのコマンドの失敗と区別する。
    SSH_FAILED = 255

    def __init__(self, destination, ssh=("ssh",)):
        self.destination = destination
        self.ssh = list(ssh)

    def _run(self, args, data=b""):
        command = " ".join(shlex.quote(a) for a in ["quaderno-archive", *args])
        result = subprocess.run(
            self.ssh + ["-o", "BatchMode=yes", self.destination, command],
            input=data, capture_output=True,
        )
        message = result.stderr.decode(errors="replace").strip()
        if result.returncode == self.SSH_FAILED:
            raise ServerUnreachable(message)
        if result.returncode != 0:
            raise ArchiveRefused(message)
        return result.stdout

    def state(self):
        return json.loads(self._run(["state"]) or b"{}")

    def store(self, entry, data):
        """置いたら True、サーバに記録済みで飛ばしたら False。"""
        out = self._run(
            ["store", entry["entry_id"], entry["file_revision"], str(len(data)), entry["entry_path"]], data
        )
        return out.decode().strip() == "placed"


def load_state(path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError:
        # 壊れた記録は空として扱う。全件を受け取り直すが、アーカイブのファイルは壊れない。
        print("状態ファイルが読めないので、記録なしとして進めます: {}".format(path), file=sys.stderr)
        return {}


def save_state(path, state):
    """一時ファイルへ書いてから置き換える。中断しても半端な記録が残らない。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True))
    tmp.replace(path)


@contextmanager
def locked(state_file, mode):
    """記録の読み書きを、ほかの機体からの同時の呼び出しと排他する。"""
    state_file.parent.mkdir(parents=True, exist_ok=True)
    with open(state_file.with_suffix(".lock"), "a") as handle:
        fcntl.flock(handle, mode)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def destination(archive_dir, entry_path):
    """デバイスの文書のパスを、アーカイブの中のパスに直す。アーカイブの外は指させない。"""
    relative = PurePosixPath(entry_path)
    if relative.is_absolute() or ".." in relative.parts or not relative.parts:
        raise ValueError("アーカイブの外を指すパスは受け取りません: {}".format(entry_path))
    return archive_dir.joinpath(*relative.parts)


def store(archive_dir, state_file, entry_id, revision, size, entry_path, source):
    """1 件を置いて記録する。置いたら True、記録済みで飛ばしたら False。"""
    target = destination(archive_dir, entry_path)
    data = source.read()
    if len(data) != size:
        raise ValueError("受け取ったサイズが一致しません: {} (期待 {} バイト、実際 {} バイト)".format(
            entry_path, size, len(data)))
    with locked(state_file, fcntl.LOCK_EX):
        state = load_state(state_file)
        if state.get(entry_id) == revision and target.exists():
            return False
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_name(target.name + ".part")
        try:
            tmp.write_bytes(data)
            tmp.replace(target)
        except BaseException:
            # 容量不足などで書き込みや置き換えが失敗しても、.part を残さない。
            # アーカイブは手動で Google Drive へ上げる単位なので、拾われない .part が溜まると邪魔になる。
            tmp.unlink(missing_ok=True)
            raise
        state[entry_id] = revision
        save_state(state_file, state)
    return True


def main(argv):
    archive_dir = Path(os.environ["QUADERNO_ARCHIVE_DIR"])
    state_file = Path(os.environ["QUADERNO_STATE_FILE"])
    if argv[1:2] == ["state"] and len(argv) == 2:
        with locked(state_file, fcntl.LOCK_SH):
            json.dump(load_state(state_file), sys.stdout, ensure_ascii=False)
        return 0
    if argv[1:2] == ["store"] and len(argv) == 6:
        _, _, entry_id, revision, size, entry_path = argv
        try:
            placed = store(archive_dir, state_file, entry_id, revision, int(size), entry_path, sys.stdin.buffer)
        except (OSError, ValueError) as e:
            print(e, file=sys.stderr)
            return 1
        print("placed" if placed else "known")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
