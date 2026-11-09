"""取り込み対象の選別と、送り先で重ならない名前の割り当てが期待どおりか。"""
from quaderno_plan import plan_downloads, plan_uploads


def doc(entry_id, path, revision):
    return {
        "entry_type": "document",
        "entry_id": entry_id,
        "entry_path": path,
        "file_revision": revision,
    }


docs = [
    {"entry_type": "folder", "entry_id": "root", "entry_path": "Document"},
    # 対象フォルダの配下にあるサブフォルダ。file_revision を持たない。entry_type の
    # ガードが無いと、prefix 判定は通ってしまい entry["file_revision"] で
    # KeyError になる。
    {"entry_type": "folder", "entry_id": "f1", "entry_path": "Document/Note"},
    doc("1", "Document/a.pdf", "r1"),
    doc("2", "Document/Note/b.pdf", "r1"),
    doc("3", "Templates/c.pdf", "r1"),
]

# 状態が空なら、対象フォルダ配下の文書だけを落とす。フォルダ自体は落とさない。
assert [d["entry_id"] for d in plan_downloads(docs, {}, "Document")] == ["1", "2"]

# 改訂が記録と一致するものは飛ばす。
assert [d["entry_id"] for d in plan_downloads(docs, {"1": "r1"}, "Document")] == ["2"]

# 改訂が変わったものは落とし直す。
assert [d["entry_id"] for d in plan_downloads(docs, {"1": "r0"}, "Document")] == ["1", "2"]

# 対象フォルダを変えれば選別も変わる。
assert [d["entry_id"] for d in plan_downloads(docs, {}, "Templates")] == ["3"]

# 名前が前方一致するだけの別フォルダを巻き込まない。
siblings = [doc("4", "Document2/d.pdf", "r1")]
assert plan_downloads(siblings, {}, "Document") == []

# 送り先に無い名前はそのまま、重なれば英字を付け、同じ回に送る別のファイルとも重ねない。
assert plan_uploads(["new.pdf", "a.pdf"], {"a.pdf"}) == [("new.pdf", "new.pdf"), ("a.pdf", "a (a).pdf")]
assert plan_uploads(["a.pdf"], {"a.pdf", "a (a).pdf"}) == [("a.pdf", "a (b).pdf")]
assert plan_uploads(["a.pdf", "a.pdf"], set()) == [("a.pdf", "a.pdf"), ("a.pdf", "a (a).pdf")]

# z の次は aa。拡張子の無い名前にも付けられる。
taken = {"a.pdf"} | {"a ({}).pdf".format(chr(c)) for c in range(ord("a"), ord("z") + 1)}
assert plan_uploads(["a.pdf"], taken) == [("a.pdf", "a (aa).pdf")]
assert plan_uploads(["memo"], {"memo"}) == [("memo", "memo (a)")]

print("Quaderno の取り込み選別と送り先の名前が期待どおり")
