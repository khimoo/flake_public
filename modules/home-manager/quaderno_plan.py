"""Quaderno の文書一覧から、取り込むべきものだけを選ぶ。

デバイスとの通信を含まないので単体テストできる。通信と入出力は quaderno_pull.py が持つ。
"""


def plan_downloads(docs, state, remote_root):
    """落とすべき文書を、デバイスが返した順序のまま返す。

    docs        DigitalPaper.traverse_folder_recursively() の戻り
    state       entry_id -> file_revision。前回までに取り込んだ記録
    remote_root デバイス上の対象フォルダ（例 "Document"）

    まだ持っていない文書と、改訂が記録と食い違う文書を選ぶ。デバイス側で削除された
    文書はここに現れないので、手元のファイルが消えることはない。
    """
    prefix = remote_root.rstrip("/") + "/"
    planned = []
    for entry in docs:
        if entry.get("entry_type") != "document":
            continue
        if not entry["entry_path"].startswith(prefix):
            continue
        if state.get(entry["entry_id"]) == entry["file_revision"]:
            continue
        planned.append(entry)
    return planned
