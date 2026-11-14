"""Quaderno と PDF を受け渡す。

  quaderno send [FILE...]   FILE を Send フォルダへコピーし、Send フォルダの PDF を Quaderno へ送る。
  quaderno receive          Quaderno の受け渡しフォルダの PDF を、手元の Received フォルダへ落とす。
  quaderno archive          Quaderno の文書を、自分用サーバのアーカイブへ取り込む。

頼まれた処理を最初に行い、つながったついでに、溜まっている送信と取り込みも済ませる。
Quaderno とつながる機会は少ない。受け取りだけは receive のときにしか行わない。
--background は定期実行のための指定で、Quaderno が見つからなくても失敗にせず、
ほかの実行が進行中なら何もしない。

取り込みは未取得・改訂された文書だけを、自分用サーバのアーカイブへ ssh で送る。取り込みの
記録もサーバが持つので、どの機体が Quaderno を見つけても同じ改訂を二度取り込まない。
送信は Send フォルダのファイルだけを、デバイス上の文書を上書きせずに送り、送れたら Send から
消す。Quaderno がスリープしていれば Send に残り、次に見つかった回に送る。
同じ LAN に見つからなければ、ペアリング済みの Digital Paper に Bluetooth の PAN をつないで探し直す。
双方向のマージはしない。設計判断は docs/architecture/quaderno.md にある。
"""
import argparse
import fcntl
import json
import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import quote_plus

import requests
from dptrp1.dptrp1 import DigitalPaper, DigitalPaperException, find_auth_files
from zeroconf import ServiceBrowser, Zeroconf

from quaderno_archive import (
    ArchiveRefused, ServerUnreachable, SshArchive, destination, load_state, save_state,
)
from quaderno_plan import plan_downloads, plan_uploads

SERVICE_TYPES = ["_digitalpaper._tcp.local.", "_dp_fujitsu._tcp.local."]


class _Finder:
    """mDNS で広告されている Digital Paper の住所を拾う。

    serial が None なら最初に見つかった一台を採る。指定されている場合は、mDNS の
    TXT レコードにシリアルが載っていないので、候補ごとに平文 HTTP の
    /register/information へ問い合わせて照合する。
    """

    def __init__(self, serial):
        self.serial = serial
        self.addr = None

    def add_service(self, zc, type_, name):
        if self.addr is not None:
            return
        info = zc.get_service_info(type_, name)
        if info is None or not info.addresses:
            return
        addr = socket.inet_ntoa(info.addresses[0])
        if self.serial is None:
            self.addr = addr
            return
        try:
            response = requests.get(
                "http://{}:{}/register/information".format(addr, info.port), timeout=5
            )
            found = response.json().get("serial_number")
        except (requests.RequestException, ValueError):
            return
        if found == self.serial:
            self.addr = addr

    def update_service(self, zc, type_, name):
        pass

    def remove_service(self, zc, type_, name):
        pass


def discover(serial, timeout):
    """接続する機器の IP を返す。見つからなければ None。

    serial が None なら最初に見つかった Digital Paper を採る。
    """
    finder = _Finder(serial)
    zc = Zeroconf()
    try:
        ServiceBrowser(zc, SERVICE_TYPES, finder)
        deadline = time.monotonic() + timeout
        while finder.addr is None and time.monotonic() < deadline:
            time.sleep(0.2)
    finally:
        zc.close()
    return finder.addr


# Bluetooth の機器名は「機種名_シリアルの末尾」の形をしている（例 FMVDP41_2006338）。
# スマホもテザリング用に NAP を公開するので、NAP の有無だけで選ぶとスマホの回線につながる。
PAN_NAME_PREFIXES = ("FMVDP", "DPT-")
PAN_PROFILE = "quaderno-pan"
LAN_FIRST_WAIT = 5


def _run(args, timeout):
    """コマンドを実行して標準出力を返す。失敗や時間切れ、コマンドが無いときは None。"""
    try:
        result = subprocess.run(
            args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout if result.returncode == 0 else None


def paired_papers():
    """ペアリング済みの Digital Paper の Bluetooth アドレスを返す。"""
    listed = _run(["bluetoothctl", "devices", "Paired"], 5)
    if listed is None:
        return []
    found = []
    for line in listed.splitlines():
        parts = line.split(" ", 2)
        if len(parts) == 3 and parts[0] == "Device" and parts[2].startswith(PAN_NAME_PREFIXES):
            found.append(parts[1])
    return found


def pan_up(bdaddr):
    """Bluetooth の PAN をつなぐ。つながれば True。

    接続プロファイルは保存せずに作り、pan_down で消す。default route は受け取らない。
    Quaderno は PAN の DHCP で default route を配るので、受け取ると Wi-Fi が無いときに
    全通信が Quaderno へ向く。
    """
    pan_down()
    added = _run(
        [
            "nmcli", "connection", "add", "save", "no", "type", "bluetooth",
            "con-name", PAN_PROFILE, "bluetooth.bdaddr", bdaddr, "bluetooth.type", "panu",
            "connection.autoconnect", "no",
            "ipv4.never-default", "yes", "ipv6.never-default", "yes",
        ],
        10,
    )
    if added is None:
        return False
    if _run(["nmcli", "--wait", "30", "connection", "up", "id", PAN_PROFILE], 40) is None:
        pan_down()
        return False
    return True


def pan_down():
    _run(["nmcli", "connection", "delete", "id", PAN_PROFILE], 10)


def connect(addr):
    """ペアリング済みの鍵で認証した接続を返す。"""
    deviceid, privatekey = find_auth_files()
    if not os.path.exists(deviceid) or not os.path.exists(privatekey):
        raise SystemExit(
            "ペアリングの記録がありません: {} と {}\n"
            "  → Quaderno の Wi-Fi を入れ、"
            "dptrp1 --addr <IP> register を一度実行してください。".format(
                deviceid, privatekey
            )
        )
    paper = DigitalPaper(addr=addr, quiet=True)
    with open(deviceid) as handle:
        client_id = handle.readline().strip()
    with open(privatekey) as handle:
        key = handle.read()
    try:
        paper.authenticate(client_id, key)
    except (requests.RequestException, KeyError, ValueError) as e:
        # このライブラリは raise_for_status を呼ばないので、HTTP エラーは
        # レスポンスを読む段で KeyError や ValueError として現れる。
        raise SystemExit(
            "認証に失敗しました: {}\n"
            "  → ペアリングが古い可能性があります。"
            "dptrp1 --addr <IP> register をやり直してください。".format(e)
        )
    return paper


def fetch(paper, entry):
    """文書 1 件を落として、中身を検査してから返す。

    paper.download() はライブラリ内部で raise_for_status() を呼ばないため、
    HTTP エラーが返ってもエラーの JSON 本文がそのまま返る。それを検査せず保存すると、
    直後に state へ改訂が記録されて二度と再取得されなくなる。書き出す前にサイズと
    （PDF なら）先頭バイトを検査し、食い違うなら呼び出し側の except に委ねて
    state を更新させない。
    """
    data = paper.download(entry["entry_path"])
    # デバイスは file_size を文字列で返す（例 "1964912"）。int に直さずに
    # len(data) と比べると常に不一致になり、全件が失敗する。
    expected_size = int(entry["file_size"])
    if len(data) != expected_size:
        raise DigitalPaperException(
            "ダウンロードしたサイズが一致しません: {} (期待 {} バイト、実際 {} バイト)".format(
                entry["entry_path"], expected_size, len(data)
            )
        )
    # mime_type が application/pdf のときだけ PDF のマジックバイトを見る。将来
    # PDF 以外のエントリが現れても、サイズ一致だけで判定できるようにしておく。
    if entry.get("mime_type") == "application/pdf" and not data.startswith(b"%PDF"):
        raise DigitalPaperException(
            "PDF として認識できない中身です: {}".format(entry["entry_path"])
        )
    return data


def settled_pdfs(send_dir, now, ready=()):
    """Send フォルダにある PDF のうち、書き込みが終わっていそうなものを返す。

    コピーの途中で送ると、半端なファイルがデバイスに残り、手元からは消える。
    ready は、このプロセスがコピーし終えたファイルの名前。更新直後でも送る。
    """
    return sorted(
        p for p in send_dir.iterdir()
        if p.is_file() and p.suffix.lower() == ".pdf"
        and (p.name in ready or now - p.stat().st_mtime > 10)
    )


def queue(send_dir, sources):
    """PDF を Send フォルダへコピーし、置いた名前を返す。同じ名前があれば新しいもので置き換える。"""
    names = []
    for source in sources:
        if source.suffix.lower() != ".pdf" or not source.is_file():
            raise SystemExit("PDF ファイルではありません: {}".format(source))
    for source in sources:
        target = send_dir / source.name
        if source.resolve() != target.resolve():
            tmp = target.with_name(target.name + ".part")
            shutil.copyfile(source, tmp)
            tmp.replace(target)
        names.append(target.name)
    return names


def create(paper, folder_id, name, handle):
    """デバイスに新しい文書を作る。同じ名前があれば作らずに例外にする。

    dptrp1 の upload は同じパスの文書を探して中身を差し替えるので使わない。
    この要求なら、名前が重なったときはデバイスが断る（error_code 40007）。
    """
    r = paper._post_endpoint(
        "/documents2",
        data={"file_name": name, "parent_folder_id": folder_id, "document_source": ""},
    )
    if not r.ok:
        raise DigitalPaperException("文書を作れません: {} ({})".format(name, r.text))
    doc_url = "/documents/{}/file".format(r.json()["document_id"])
    r = paper._put_endpoint(doc_url, files={"file": (quote_plus(name), handle, "rb")})
    if not r.ok:
        raise DigitalPaperException("中身を送れません: {} ({})".format(name, r.text))


def send(paper, send_dir, remote_dir, docs, ready):
    """Send フォルダの PDF を送る。送れたものは Send から消す。失敗が一つでもあれば 1。"""
    files = {p.name: p for p in settled_pdfs(send_dir, time.time(), ready)}
    if not files:
        return 0
    prefix = remote_dir.rstrip("/") + "/"
    taken = {
        entry["entry_path"][len(prefix):]
        for entry in docs
        if entry["entry_path"].startswith(prefix) and "/" not in entry["entry_path"][len(prefix):]
    }
    try:
        folder_id = paper._get_object_id(remote_dir)
    except (requests.RequestException, DigitalPaperException, KeyError, ValueError) as e:
        print("送り先のフォルダが見つかりません: {} ({})".format(remote_dir, e))
        return 1
    status = 0
    for name, target in plan_uploads(sorted(files), taken):
        local = files[name]
        path = prefix + target
        try:
            with open(local, "rb") as handle:
                create(paper, folder_id, target, handle)
            info = paper.list_document_info(path)
            if int(info["file_size"]) != local.stat().st_size:
                raise DigitalPaperException(
                    "送ったサイズが一致しません: {} (手元 {} バイト、デバイス {} バイト)".format(
                        path, local.stat().st_size, info["file_size"]
                    )
                )
        except (requests.RequestException, OSError, DigitalPaperException, KeyError, ValueError) as e:
            print("送信に失敗: {} ({})".format(path, e))
            status = 1
            continue
        local.unlink()
        print("  送信: {}".format(path))
    return status


def receive(paper, docs, receive_dir, state_file, remote_dir):
    """デバイスの remote_dir の文書のうち、未取得か改訂されたものを receive_dir へ落とす。

    記録は手元に持ち、自分用サーバを使わない。失敗が一つでもあれば 1。
    """
    state = load_state(state_file)
    prefix = remote_dir.rstrip("/") + "/"
    status = 0
    for entry in plan_downloads(docs, state, remote_dir):
        try:
            target = destination(receive_dir, entry["entry_path"][len(prefix):])
            data = fetch(paper, entry)
            target.parent.mkdir(parents=True, exist_ok=True)
            tmp = target.with_name(target.name + ".part")
            try:
                tmp.write_bytes(data)
                tmp.replace(target)
            except BaseException:
                tmp.unlink(missing_ok=True)
                raise
        except (requests.RequestException, OSError, DigitalPaperException, KeyError, ValueError) as e:
            print("受け取りに失敗: {} ({})".format(entry["entry_path"], e))
            status = 1
            continue
        state[entry["entry_id"]] = entry["file_revision"]
        save_state(state_file, state)
        print("  受け取り: {} ({} バイト)".format(target, len(data)))
    return status


def main(argv):
    parser = argparse.ArgumentParser(prog="quaderno", description="Quaderno と PDF を受け渡す。")
    commands = parser.add_subparsers(dest="command", required=True, metavar="{send,receive,archive}")
    background = argparse.ArgumentParser(add_help=False)
    background.add_argument("--background", action="store_true", help="定期実行のための指定")
    sending = commands.add_parser("send", parents=[background], help="Send フォルダの PDF を Quaderno へ送る")
    sending.add_argument("files", nargs="*", type=Path, metavar="FILE", help="先に Send フォルダへコピーする PDF")
    commands.add_parser("receive", parents=[background], help="受け渡しフォルダの PDF を手元へ落とす")
    commands.add_parser("archive", parents=[background], help="文書を自分用サーバのアーカイブへ取り込む")
    args = parser.parse_args(argv[1:])

    # 空文字は「指定なし」を意味する。Nix 側は null をこの形で渡す。
    serial = os.environ.get("QUADERNO_SERIAL") or None
    timeout = int(os.environ.get("QUADERNO_DISCOVERY_TIMEOUT", "15"))
    # 取り込みと受け渡しフォルダは、利用者に入った要素（use_quaderno_archive、quaderno_exchange）の分だけ設定される。
    archive = os.environ.get("QUADERNO_ARCHIVE_SSH")
    remote_root = os.environ.get("QUADERNO_REMOTE_ROOT", "Document")
    exchange_remote = os.environ.get("QUADERNO_EXCHANGE_REMOTE")
    if args.command in ("send", "receive") and not exchange_remote:
        print("受け渡しフォルダの設定がありません（要素 quaderno_exchange が入っていません）。")
        return 1
    if args.command == "archive" and not archive:
        print("アーカイブの設定がありません（要素 use_quaderno_archive が入っていません）。")
        return 1
    # 文書一覧は一度だけ取る。送り先にある名前も、受け取る文書も、その一覧から知る。
    listed = remote_root if archive else exchange_remote
    root = listed.rstrip("/")
    if exchange_remote and exchange_remote.rstrip("/") != root and not exchange_remote.startswith(root + "/"):
        print("受け渡しフォルダ {} が、取り込み対象 {} の外にあります。".format(exchange_remote, listed))
        return 1
    job = Job(listed, archive, remote_root, exchange_remote)
    if exchange_remote:
        job.send_dir = Path(os.environ["QUADERNO_SEND_DIR"])
        # 置き場所が無いと、送りたいときに作り方が分からない。見つからない回でも作っておく。
        job.send_dir.mkdir(parents=True, exist_ok=True)
    if args.command == "send":
        job.ready = queue(job.send_dir, args.files)
    if args.command == "receive":
        job.receive_dir = Path(os.environ["QUADERNO_RECEIVE_DIR"])
        job.receive_state = Path(os.environ["QUADERNO_RECEIVE_STATE"])
        job.receive_dir.mkdir(parents=True, exist_ok=True)
    # 頼まれた処理が先。未取り込みの文書が多いときに、送信や受け取りを取り込みの後ろで待たせない。
    job.steps = {
        "send": ["send", "pull"],
        "receive": ["receive", "send", "pull"],
        "archive": ["pull", "send"],
    }[args.command]

    # 定期実行とコマンドが同時に Quaderno へつなぐと、PAN の接続と切断が互いを壊す。
    lock_dir = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")
    with open(lock_dir / "quaderno.lock", "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | (fcntl.LOCK_NB if args.background else 0))
        except BlockingIOError:
            return 0
        addr, raised = find(serial, timeout)
        try:
            if addr is None:
                return missing(job, args)
            return transfer(addr, job)
        finally:
            if raised:
                pan_down()


class Job:
    """一度の接続で行うこと。"""

    def __init__(self, listed, archive, remote_root, exchange_remote):
        self.listed = listed
        self.archive = archive
        self.remote_root = remote_root
        self.exchange_remote = exchange_remote
        self.send_dir = None
        self.ready = []
        self.receive_dir = None
        self.receive_state = None
        self.steps = []


def missing(job, args):
    """Quaderno が見つからなかったときの終了コードを返す。

    スリープ中は Wi-Fi も Bluetooth も切れている。send は PDF が Send に残って後で送られるので、
    頼まれたことは果たされる。receive と archive は何も起きていないので、人が頼んだときは失敗にする。
    """
    print("Quaderno が見つかりません（スリープ中とみられます）。")
    if job.send_dir and settled_pdfs(job.send_dir, time.time(), job.ready):
        print("  Send フォルダの PDF は、次に Quaderno が見つかったときに送ります。")
    if args.background or args.command == "send":
        return 0
    print("  → Quaderno のスリープを解除してから、もう一度実行してください。")
    return 1


def find(serial, timeout):
    """Quaderno の IP と、この実行が PAN をつないだかを返す。見つからなければ IP は None。"""
    # Bluetooth しか使えない場所で待たされないよう、LAN は短く探してから PAN を試す。
    # LAN の応答が遅かった場合に備えて、PAN で見つからなければ残りの時間で LAN を探し直す。
    deadline = time.monotonic() + timeout
    addr = discover(serial, min(LAN_FIRST_WAIT, timeout))
    raised = False
    if addr is None:
        for bdaddr in paired_papers():
            if pan_up(bdaddr):
                # zeroconf は作った時点のインターフェースしか見ない。PAN をつないだ後に探し直す。
                raised = True
                addr = discover(serial, timeout)
                break
    if addr is None and not raised and deadline > time.monotonic():
        addr = discover(serial, deadline - time.monotonic())
    return addr, raised


def transfer(addr, job):
    paper = connect(addr)
    try:
        if job.exchange_remote and not paper.path_exists(job.exchange_remote):
            # new_folder は応答を確かめない。作れたかは、もう一度パスを引いて確かめる。
            paper.new_folder(job.exchange_remote)
            if not paper.path_exists(job.exchange_remote):
                print("受け渡しフォルダを作れません: {}".format(job.exchange_remote))
                return 1
            print("受け渡しフォルダを作りました: {}".format(job.exchange_remote))
        docs = paper.traverse_folder_recursively(job.listed)
    except DigitalPaperException as e:
        # フォルダはホストの値で変えられるので、設定ミスをそれと分かる形で伝える。
        print("文書フォルダが見つかりません: {} ({})".format(job.listed, e))
        print("  → ホストの quaderno_remote_root と quaderno_exchange_remote を確かめてください。")
        return 1
    except requests.RequestException as e:
        print("文書一覧の取得中に通信が切れました: {}".format(e))
        print("  → デバイスの Wi-Fi が有効か確かめてください。")
        return 1
    except (KeyError, ValueError) as e:
        # traverse_folder_recursively は .json()['entry_list'] を無検査で引く。
        # セッション切れなどで HTTP エラーが返ると、ここで KeyError や ValueError になる。
        print("文書一覧の取得に失敗しました: {}".format(e))
        print("  → セッションが切れている可能性があります。しばらくしてから再実行してください。")
        return 1
    print("{} に接続しました。".format(addr))
    status = 0
    for step in job.steps:
        if step == "pull" and job.archive:
            status = max(status, pull(paper, docs, SshArchive(job.archive), job.remote_root, addr))
        if step == "receive":
            status = max(status, receive(paper, docs, job.receive_dir, job.receive_state, job.exchange_remote))
        if step == "send" and job.send_dir:
            status = max(status, send(paper, job.send_dir, job.exchange_remote, docs, job.ready))
    return status


def pull(paper, docs, archive, remote_root, addr):
    try:
        state = archive.state()
    except ServerUnreachable as e:
        # 出先で自分用サーバに届かないときは、文書を Quaderno に残して次の機会に取り込む。
        print("自分用サーバ {} に接続できないので、取り込みは次の機会にします。({})".format(archive.destination, e))
        return 0
    except (ArchiveRefused, OSError, ValueError) as e:
        print("自分用サーバから取り込みの記録を読めません: {}".format(e))
        return 1
    planned = plan_downloads(docs, state, remote_root)
    if not planned:
        return 0

    print("{} 件を取り込みます。".format(len(planned)))
    for entry in planned:
        try:
            data = fetch(paper, entry)
            # サーバは 1 件ごとに記録を更新する。途中で落ちても、済んだ分は次回落とし直さない。
            placed = archive.store(entry, data)
            print("  {}: {} ({} バイト)".format("取り込み" if placed else "取り込み済み", entry["entry_path"], len(data)))
        except ServerUnreachable as e:
            print("自分用サーバとの接続が切れました: {}".format(e))
            print("  済んだ分はサーバに記録されています。次回の実行が続きから取り込みます。")
            return 1
        except (requests.RequestException, OSError, DigitalPaperException, ArchiveRefused, KeyError, ValueError) as e:
            # requests: 通信断。OSError: ssh を起動できないなど。
            # DigitalPaperException: 文書が途中で消えた、またはダウンロード内容の検証に失敗。
            # ArchiveRefused: サーバがパスやサイズを理由に受け取りを断った。
            # KeyError/ValueError: セッション切れ等で HTTP エラーの JSON がそのまま返った場合。
            print("取り込みに失敗: {} ({})".format(entry["entry_path"], e))
            print("  済んだ分はサーバに記録されています。次回の実行が続きから取り込みます。")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
