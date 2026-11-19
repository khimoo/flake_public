#!/usr/bin/env python3
"""Synchronize declarative settings into mutable Hermes profile config.yaml files.

Preserves runtime keys written by Hermes (such as _config_version) while ensuring
each aiboard-* profile has the declared model, toolsets, skills, memory, and
(for vertex profiles) sops-decrypted vertex/providers settings.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

import yaml


def deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    out = copy.deepcopy(base)
    for k, v in overlay.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def sync_profiles(
    home: Path,
    manifest: dict[str, Any],
    vertex_secret_path: Path | None,
    *,
    dry_run: bool = False,
) -> int:
    vertex_overlay: dict[str, Any] | None = None
    needs_vertex = any(spec.get("uses_vertex_secret") for spec in manifest.values())
    if needs_vertex:
        if vertex_secret_path is None or not vertex_secret_path.is_file():
            if dry_run:
                print(
                    f"aiboard-profiles: (dry-run) {vertex_secret_path} が未配置のため vertex 設定の合成は本番実行時に行う",
                    file=sys.stderr,
                )
            else:
                print(
                    f"aiboard-profiles: vertex 設定ファイル {vertex_secret_path} が見つからない（secrets activation を確認）",
                    file=sys.stderr,
                )
                return 1
        else:
            loaded = yaml.safe_load(vertex_secret_path.read_text(encoding="utf-8"))
            if not isinstance(loaded, dict):
                print(f"aiboard-profiles: {vertex_secret_path} の形式が不正（YAML マップが必要）", file=sys.stderr)
                return 1
            vertex_overlay = {k: loaded[k] for k in ("vertex", "providers") if k in loaded}

    shared_skills_dir = str(home / ".hermes" / "skills")
    profiles_root = home / ".hermes" / "profiles"

    for profile_name, spec in sorted(manifest.items()):
        pdir = profiles_root / profile_name
        cfg_path = pdir / "config.yaml"
        if cfg_path.is_symlink() or (cfg_path.exists() and not cfg_path.is_file()):
            print(f"aiboard-profiles: {cfg_path}: 通常のファイルでないので触らない", file=sys.stderr)
            continue

        existing: dict[str, Any] = {}
        existing_raw: str | None = None
        if cfg_path.is_file():
            existing_raw = cfg_path.read_text(encoding="utf-8")
            parsed = yaml.safe_load(existing_raw)
            if parsed is None:
                existing = {}
            elif isinstance(parsed, dict):
                existing = parsed
            else:
                print(f"aiboard-profiles: {cfg_path}: YAML マップでないため上書きを中止", file=sys.stderr)
                return 1

        overlay = copy.deepcopy(spec["config"])
        overlay.setdefault("skills", {})["external_dirs"] = [shared_skills_dir]
        if spec.get("uses_vertex_secret") and vertex_overlay:
            overlay = deep_merge(overlay, vertex_overlay)

        merged = deep_merge(existing, overlay)
        merged.setdefault("_config_version", 52)
        rendered = yaml.safe_dump(merged, sort_keys=False, allow_unicode=True)
        mode = 0o600 if spec.get("uses_vertex_secret") else 0o644

        if dry_run:
            state = "unchanged" if existing_raw == rendered else ("update" if existing_raw is not None else "create")
            print(f"aiboard-profiles: (dry-run) {cfg_path} ({state}, mode={oct(mode)[2:]})", file=sys.stderr)
            continue

        pdir.mkdir(parents=True, exist_ok=True)
        if existing_raw == rendered:
            os.chmod(cfg_path, mode)
            continue

        fd, tmp_name = tempfile.mkstemp(prefix=".config.yaml.", dir=str(pdir))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(rendered)
            os.chmod(tmp_name, mode)
            os.replace(tmp_name, cfg_path)
        except BaseException:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)
            raise

    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Sync aiboard Hermes profile config.yaml files")
    parser.add_argument("--home", required=True, help="Target user home directory")
    parser.add_argument("--manifest", required=True, help="Path to JSON profile manifest")
    parser.add_argument("--vertex-secret", help="Path to sops-decrypted vertex-provider.yaml")
    parser.add_argument("--dry-run", action="store_true", help="Do not write files")
    args = parser.parse_args(argv)
    dry_run = args.dry_run or bool(os.environ.get("DRY_RUN_CMD"))
    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    vertex_path = Path(args.vertex_secret) if args.vertex_secret else None
    return sync_profiles(Path(args.home), manifest, vertex_path, dry_run=dry_run)


if __name__ == "__main__":
    sys.exit(main())
