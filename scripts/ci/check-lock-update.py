"""Allow changes to existing pins, not to the flake input graph or its sources."""
import argparse
import json
from pathlib import Path
import re

PIN_FIELDS = ("rev", "narHash", "lastModified")


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError(f"invalid JSON constant: {value}")


def read_lock(path):
    lock = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_keys,
                      parse_constant=reject_constant)
    if not isinstance(lock, dict) or not isinstance(lock.get("nodes"), dict):
        raise ValueError("expected a lock file with a nodes object")
    return lock


def split_pins(node):
    if not isinstance(node, dict):
        raise ValueError("expected each lock node to be an object")
    if "locked" not in node:
        return node, {}
    locked = node["locked"]
    if not isinstance(locked, dict):
        raise ValueError("expected the locked source to be an object")
    source = {key: value for key, value in locked.items() if key not in PIN_FIELDS}
    pins = {key: locked[key] for key in PIN_FIELDS if key in locked}
    return {**node, "locked": source}, pins


def same_json(before, after):
    # In Python, e.g. 1 == True; that is not an unchanged JSON field.
    return json.dumps(before, sort_keys=True) == json.dumps(after, sort_keys=True)


def valid_pin(key, value):
    if key == "lastModified":
        return type(value) is int and value >= 0
    pattern = {"rev": r"[0-9a-f]{40}", "narHash": r"sha256-[A-Za-z0-9+/]{43}="}[key]
    return isinstance(value, str) and re.fullmatch(pattern, value) is not None


def compare(before, after):
    if not same_json({k: v for k, v in before.items() if k != "nodes"},
                     {k: v for k, v in after.items() if k != "nodes"}):
        raise ValueError("lock root, version or top-level metadata changed")
    if before["nodes"].keys() != after["nodes"].keys():
        raise ValueError("lock nodes were added or removed; update the input graph manually")
    changes = []
    for name in sorted(before["nodes"]):
        old_source, old_pins = split_pins(before["nodes"][name])
        new_source, new_pins = split_pins(after["nodes"][name])
        if not same_json(old_source, new_source):
            raise ValueError(f"input graph or source changed for {name!r}; update manually")
        if old_pins.keys() != new_pins.keys():
            raise ValueError(f"pin fields were added or removed for {name!r}")
        for key, value in new_pins.items():
            if not valid_pin(key, value):
                raise ValueError(f"invalid {key} for {name!r}")
        fields = [(key, old_pins[key], new_pins[key]) for key in new_pins
                  if old_pins[key] != new_pins[key]]
        if fields:
            changes.append((name, fields))
    if not changes:
        raise ValueError("no input pins changed")
    return changes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()
    try:
        changes = compare(read_lock(args.before), read_lock(args.after))
    except (ValueError, OSError) as error:
        parser.exit(1, f"lock update rejected: {error}\n")
    print("### Updated lock nodes\n")
    for name, fields in changes:
        print(f"- `{name}`")
        for key, before, after in fields:
            print(f"  - `{key}`: `{before}` → `{after}`")


if __name__ == "__main__":
    main()
