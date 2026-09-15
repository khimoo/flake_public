"""Quaderno から未取得・改訂された文書だけをアーカイブへ取り込む。

一方向。手元からデバイスへは何も書かないし、手元のファイルも消さない。
設計判断は docs/architecture/quaderno.md にある。
"""
import json
import os
import socket
import sys
import time
from pathlib import Path

import requests
from dptrp1.dptrp1 import DigitalPaper, DigitalPaperException, find_auth_files
from zeroconf import ServiceBrowser, Zeroconf

from quaderno_plan import plan_downloads

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


def load_state(path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError:
        # 壊れた記録は空として扱う。全件落とし直すが、手元のファイルは壊れない。
        print("状態ファイルが読めないので、記録なしとして進めます: {}".format(path))
        return {}


def save_state(path, state):
    """一時ファイルへ書いてから置き換える。中断しても半端な記録が残らない。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True))
    tmp.replace(path)


def store(paper, entry, archive_dir):
    """文書 1 件を落として、アーカイブ内の同じ相対パスへ置く。

    paper.download() はライブラリ内部で raise_for_status() を呼ばないため、
    HTTP エラーが返ってもエラーの JSON 本文がそのまま返る。それを検査せず保存すると、
    直後に state へ改訂が記録されて二度と再取得されなくなる。書き出す前にサイズと
    （PDF なら）先頭バイトを検査し、食い違うなら呼び出し側の except に委ねて
    state を更新させない。
    """
    destination = archive_dir / entry["entry_path"]
    destination.parent.mkdir(parents=True, exist_ok=True)
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
    tmp = destination.with_name(destination.name + ".part")
    try:
        tmp.write_bytes(data)
        tmp.replace(destination)
    except BaseException:
        # 容量不足などで書き込みや置き換えが失敗しても、.part を残さない。
        # 取り込み先は手動で Google Drive へ上げる単位なので、拾われない .part が
        # 溜まると邪魔になる。
        tmp.unlink(missing_ok=True)
        raise
    return len(data)


def main():
    # 空文字は「指定なし」を意味する。Nix 側は null をこの形で渡す。
    serial = os.environ.get("QUADERNO_SERIAL") or None
    archive_dir = Path(os.environ["QUADERNO_ARCHIVE_DIR"])
    remote_root = os.environ.get("QUADERNO_REMOTE_ROOT", "Document")
    timeout = int(os.environ.get("QUADERNO_DISCOVERY_TIMEOUT", "15"))
    state_file = Path(os.environ["QUADERNO_STATE_FILE"])

    addr = discover(serial, timeout)
    if addr is None:
        # スリープ中は Wi-Fi ごと落ちる。これは異常ではない。
        print("Quaderno が見つかりません（スリープ中とみられます）。何もしません。")
        return 0

    paper = connect(addr)
    state = load_state(state_file)
    try:
        docs = paper.traverse_folder_recursively(remote_root)
    except DigitalPaperException as e:
        # remote_root が設定で変えられる値なので、設定ミスをそれと分かる形で伝える。
        print("文書フォルダが見つかりません: {} ({})".format(remote_root, e))
        print("  → local.quaderno.remoteRoot の設定値を確かめてください。")
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
    planned = plan_downloads(docs, state, remote_root)
    if not planned:
        print("{} に接続しました。新しい文書はありません。".format(addr))
        return 0

    print("{} に接続しました。{} 件を取り込みます。".format(addr, len(planned)))
    for entry in planned:
        try:
            size = store(paper, entry, archive_dir)
            state[entry["entry_id"]] = entry["file_revision"]
            # 1 件ごとに記録を更新する。途中で落ちても、済んだ分は次回落とし直さない。
            save_state(state_file, state)
            print("  取り込み: {} ({} バイト)".format(entry["entry_path"], size))
        except (requests.RequestException, OSError, DigitalPaperException, KeyError, ValueError) as e:
            # requests: 通信断。OSError: ファイル I/O 失敗（容量不足など）。
            # DigitalPaperException: 文書が途中で消えた、またはダウンロード内容の検証に失敗。
            # KeyError/ValueError: セッション切れ等で HTTP エラーの JSON がそのまま返った場合。
            print("取り込みに失敗: {} ({})".format(entry["entry_path"], e))
            print("  状態ファイルは{}まで更新されています。次回の実行が続きから取り込みます。".format(state_file))
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
