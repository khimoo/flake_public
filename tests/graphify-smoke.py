"""Exercise the installed CLI and Rust grammar, including stale-node removal."""
import json
import subprocess
import tempfile
from pathlib import Path

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / "lib.rs").write_text("pub fn grow(water: u32) -> u32 { water + 1 }\n")
    (root / "old.rs").write_text("pub struct RemovedPlant;\n")

    def extract():
        subprocess.run(["graphify", "extract", str(root), "--code-only", "--max-workers", "1", "--force"], check=True)
        return json.loads((root / "graphify-out/graph.json").read_text())["nodes"]

    nodes = extract()
    assert any("grow" in n["label"] and n.get("source_location") for n in nodes), nodes
    assert any("RemovedPlant" in n["label"] for n in nodes), nodes
    query = subprocess.check_output(["graphify", "query", "grow", "--graph", str(root / "graphify-out/graph.json"), "--budget", "500"], text=True)
    assert "lib.rs" in query, query
    (root / "old.rs").unlink()
    (root / "lib.rs").rename(root / "plant.rs")
    nodes = extract()
    assert not any("RemovedPlant" in n["label"] or n.get("source_file", "").endswith(("old.rs", "lib.rs")) for n in nodes), nodes
    assert any(n.get("source_file", "").endswith("plant.rs") for n in nodes), nodes
print("Graphify Rust extraction, query and deletion/rename passed")
