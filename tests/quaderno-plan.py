"""取り込み対象の選別が、フォルダ・対象外パス・既取得・改訂をそれぞれ正しく扱うか。"""
from quaderno_plan import plan_downloads


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

print("Quaderno の取り込み選別が期待どおり")
