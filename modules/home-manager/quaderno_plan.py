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



def plan_uploads(names, taken):
    """Send フォルダの各ファイルに、送り先で重ならない名前を割り当てる。

    names Send フォルダにある PDF のファイル名
    taken 送り先のフォルダにすでにある文書の名前の集合

    デバイスは同じフォルダに同じ名前の文書を作れない（error_code 40007）。上書きすると
    デバイス上の書き込みが消えるので、空いていなければ "a (a).pdf"、"a (b).pdf" … と
    英字を付ける。数字にしないのは、デバイスや別の道具が付けた番号と見分けるため。
    (name, 送り先での名前) を返す。
    """
    used = set(taken)
    planned = []
    for name in names:
        target = name
        n = 0
        while target in used:
            target = _with_label(name, _letters(n))
            n += 1
        used.add(target)
        planned.append((name, target))
    return planned


def _letters(n):
    """0 -> "a"、25 -> "z"、26 -> "aa" のように、表計算の列名と同じ順で返す。"""
    label = ""
    n += 1
    while n:
        n, r = divmod(n - 1, 26)
        label = chr(ord("a") + r) + label
    return label


def _with_label(name, label):
    stem, dot, suffix = name.rpartition(".")
    if not dot:
        return "{} ({})".format(name, label)
    return "{} ({}).{}".format(stem, label, suffix)
