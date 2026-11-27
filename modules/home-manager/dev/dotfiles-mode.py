import argparse
import json
import os
import pathlib
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile


def load_manifest(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict) or not isinstance(data.get("items"), list):
        raise ValueError(f"invalid manifest: {path}")
    return data


def state_home_dir():
    xdg_state = os.environ.get("XDG_STATE_HOME", "").strip()
    if xdg_state:
        return pathlib.Path(xdg_state)
    home = os.environ.get("HOME", "")
    if home:
        return pathlib.Path(home) / ".local" / "state"
    return pathlib.Path.home() / ".local" / "state"


def run_cmd(argv):
    return subprocess.run(argv, capture_output=True, text=True, check=False)


def notify(title, body="", quiet=False):
    if quiet or not shutil.which("notify-send"):
        return
    cmd = [
        "notify-send",
        "--app-name=dotfiles-mode",
        "-h",
        "string:x-canonical-private-synchronous:dotfiles-mode",
        title,
    ]
    if body:
        cmd.append(body)
    run_cmd(cmd)


def atomic_symlink(link_path, target):
    """link_path を target へのシンボリックリンクへ原子的に更新する。変更があれば True。"""
    link_path = pathlib.Path(link_path)
    if os.path.lexists(link_path):
        if not os.path.islink(link_path):
            raise RuntimeError(f"{link_path} はシンボリックリンクではないため変更しません")
        if os.readlink(link_path) == target:
            return False
    link_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = link_path.parent / f".{link_path.name}.tmp.{os.getpid()}.{secrets.token_hex(4)}"
    os.symlink(target, tmp_path)
    try:
        os.replace(tmp_path, link_path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    return True


def atomic_write_bytes(dest_path, content, mode=0o644):
    dest_path = pathlib.Path(dest_path)
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    if dest_path.is_file() and not dest_path.is_symlink():
        try:
            if dest_path.read_bytes() == content:
                os.chmod(dest_path, mode)
                return False
        except OSError:
            pass
    fd, tmp_name = tempfile.mkstemp(prefix=f".{dest_path.name}.", dir=str(dest_path.parent))
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(content)
        os.chmod(tmp_name, mode)
        os.replace(tmp_name, dest_path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise
    return True


def sync_nvim_lockfile(store_dir, dry_run=False):
    src = pathlib.Path(store_dir) / "lazy-lock.json"
    if not src.is_file():
        return
    dst = state_home_dir() / "nvim" / "lazy-lock.json"
    if os.path.islink(dst) or (dst.exists() and not dst.is_file()):
        print(f"dotfiles-mode: {dst} は通常のファイルではないため触りません", file=sys.stderr)
        return
    if dry_run:
        print(f"dotfiles-mode: (dry-run) {dst} を store 版の lazy-lock.json に揃える予定", file=sys.stderr)
        return
    atomic_write_bytes(dst, src.read_bytes(), mode=0o644)


def signal_kitty_reload():
    proc_root = pathlib.Path("/proc")
    if not proc_root.is_dir():
        return
    uid = os.getuid()
    for entry in proc_root.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != uid:
                continue
            raw = (entry / "cmdline").read_bytes()
        except OSError:
            continue
        if not raw:
            continue
        argv0 = raw.split(b"\x00", 1)[0].decode("utf-8", errors="ignore")
        if os.path.basename(argv0) in ("kitty", ".kitty-wrapped"):
            try:
                os.kill(int(entry.name), signal.SIGUSR1)
            except OSError:
                pass


def reload_target(reload_kind):
    if reload_kind == "niri":
        if shutil.which("niri"):
            run_cmd(["niri", "msg", "action", "load-config-file"])
    elif reload_kind == "kanshi":
        if shutil.which("kanshictl"):
            run_cmd(["kanshictl", "reload"])
    elif reload_kind == "kitty":
        signal_kitty_reload()
    elif reload_kind == "quickshell":
        if shutil.which("systemctl"):
            run_cmd(["systemctl", "--user", "restart", "--no-block", "quickshell-hub.service"])


def item_status(links_dir, item):
    link_path = pathlib.Path(links_dir) / item["name"]
    target = ""
    mode = "missing"
    if os.path.islink(link_path):
        target = os.readlink(link_path)
        if target == item["dev"]:
            mode = "dev"
        elif target == item["store"]:
            mode = "store"
        else:
            mode = "other"
    elif os.path.lexists(link_path):
        mode = "other"
    return {
        "name": item["name"],
        "label": item["label"],
        "mode": mode,
        "dev": mode == "dev",
        "dev_available": os.path.exists(item["dev"]),
        "target": target,
    }


def status_payload(manifest):
    links_dir = manifest["links_dir"]
    statuses = [item_status(links_dir, item) for item in manifest["items"]]
    return {
        "any_dev": any(s["dev"] for s in statuses),
        "items": statuses,
    }


def find_item(manifest, name):
    for item in manifest["items"]:
        if item["name"] == name:
            return item
    return None


def switch_item(manifest, item, to_dev, no_reload=False, quiet=False):
    links_dir = manifest["links_dir"]
    link_path = pathlib.Path(links_dir) / item["name"]
    if to_dev:
        if not os.path.exists(item["dev"]):
            msg = f"{item['label']}: {item['dev']} が見つかりません"
            print(f"dotfiles-mode: {msg}", file=sys.stderr)
            notify("Dev モードに切り替えられません", msg, quiet=quiet)
            return 1
        atomic_symlink(link_path, item["dev"])
        notify(f"Dev モード: {item['label']} → ON", "checkout を参照中", quiet=quiet)
    else:
        atomic_symlink(link_path, item["store"])
        if item["name"] == "nvim":
            sync_nvim_lockfile(item["store"])
        notify(f"Dev モード: {item['label']} → OFF", "Nix store を参照中", quiet=quiet)

    if not no_reload:
        reload_target(item.get("reload", "none"))
    return 0


def reset_all(manifest, no_reload=False, quiet=False):
    links_dir = manifest["links_dir"]
    changed_items = []
    for item in manifest["items"]:
        link_path = pathlib.Path(links_dir) / item["name"]
        if atomic_symlink(link_path, item["store"]):
            changed_items.append(item)
        if item["name"] == "nvim":
            sync_nvim_lockfile(item["store"])

    if changed_items:
        labels = ", ".join(i["label"] for i in changed_items)
        notify("Dev モード: 全て OFF に戻しました", labels, quiet=quiet)

    if not no_reload and changed_items:
        # quickshell-hub は自身のプロセスを再起動するため、他の対象を反映した最後に実行する。
        reloads = [i.get("reload", "none") for i in changed_items]
        for kind in reloads:
            if kind != "quickshell":
                reload_target(kind)
        if "quickshell" in reloads:
            reload_target("quickshell")
    return 0


def sync_store(manifest, dry_run=False):
    state_dir = pathlib.Path(manifest["state_dir"])
    links_dir = pathlib.Path(manifest["links_dir"])
    managed_file = state_dir / "managed"
    items = manifest["items"]

    if not items and not managed_file.is_file():
        return 0

    declared_names = [item["name"] for item in items]
    declared_set = set(declared_names)

    for item in items:
        link_path = links_dir / item["name"]
        if dry_run:
            print(
                f"dotfiles-mode: (dry-run) {link_path} -> {item['store']} へ揃える予定",
                file=sys.stderr,
            )
        else:
            atomic_symlink(link_path, item["store"])
        if item["name"] == "nvim":
            sync_nvim_lockfile(item["store"], dry_run=dry_run)

    if managed_file.is_file():
        for raw_line in managed_file.read_text(encoding="utf-8").splitlines():
            old_name = raw_line.strip()
            if not old_name or old_name in declared_set:
                continue
            old_link = links_dir / old_name
            if dry_run:
                print(
                    f"dotfiles-mode: (dry-run) {old_link} は宣言から外れたため削除予定",
                    file=sys.stderr,
                )
            elif os.path.islink(old_link):
                os.unlink(old_link)
            elif os.path.lexists(old_link):
                print(
                    f"dotfiles-mode: {old_link} はシンボリックリンクではないため削除しません",
                    file=sys.stderr,
                )

    if not dry_run:
        managed_body = ("\n".join(sorted(declared_names)) + "\n") if declared_names else ""
        atomic_write_bytes(managed_file, managed_body.encode("utf-8"), mode=0o644)
    return 0


def print_status_text(payload):
    items = payload["items"]
    if not items:
        print("dotfiles-mode: 管理対象はありません")
        return
    width = max(len(item["name"]) for item in items)
    for item in items:
        suffix = "" if item["dev_available"] else " (checkout なし)"
        print(f"{item['name']:<{width}}  {item['mode']:<7}  -> {item['target']}{suffix}")


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="dotfiles-mode",
        description="Nix store（既定）とローカル checkout（Dev モード）の間で設定リンクを個別に切り替える。",
    )
    parser.add_argument(
        "--manifest",
        default=os.environ.get("DOTFILES_MODE_MANIFEST", ""),
        help="対象定義 JSON のパス（既定: DOTFILES_MODE_MANIFEST）",
    )
    parser.add_argument(
        "--status-json",
        action="store_true",
        help="現在の状態を JSON で出力する（status --json と同等）",
    )
    sub = parser.add_subparsers(dest="command")

    p_status = sub.add_parser("status", help="各対象の状態を表示する")
    p_status.add_argument("--json", action="store_true", dest="as_json", help="JSON 形式で出力する")

    for cmd_name, help_text in (
        ("toggle", "指定対象の store / dev を切り替える"),
        ("on", "指定対象を Dev モード（checkout）へ切り替える"),
        ("off", "指定対象を通常モード（Nix store）へ戻す"),
    ):
        p_cmd = sub.add_parser(cmd_name, help=help_text)
        p_cmd.add_argument("target", help="対象名（例: niri, quickshell, kanshi, kitty, nvim）")
        p_cmd.add_argument("--no-reload", action="store_true", help="アプリの再読み込みを行わない")
        p_cmd.add_argument("--quiet", action="store_true", help="デスクトップ通知を出さない")

    p_reset = sub.add_parser("reset", help="全対象を通常モード（Nix store）へ戻す")
    p_reset.add_argument("--no-reload", action="store_true", help="アプリの再読み込みを行わない")
    p_reset.add_argument("--quiet", action="store_true", help="デスクトップ通知を出さない")

    p_sync = sub.add_parser("sync-store", help="activation 用: 全対象を Nix store へ揃え、不要リンクを掃除する")
    p_sync.add_argument("--dry-run", action="store_true", help="ファイルシステムを変更せず予定だけ出力する")

    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    if not args.manifest:
        print("dotfiles-mode: --manifest または DOTFILES_MODE_MANIFEST を指定してください", file=sys.stderr)
        return 2
    try:
        manifest = load_manifest(args.manifest)
        if args.status_json or (args.command == "status" and args.as_json):
            print(json.dumps(status_payload(manifest), ensure_ascii=False))
            return 0
        if args.command in (None, "status"):
            print_status_text(status_payload(manifest))
            return 0
        if args.command == "sync-store":
            return sync_store(manifest, dry_run=args.dry_run)
        if args.command == "reset":
            return reset_all(manifest, no_reload=args.no_reload, quiet=args.quiet)
        if args.command in ("toggle", "on", "off"):
            item = find_item(manifest, args.target)
            if item is None:
                names = ", ".join(i["name"] for i in manifest["items"])
                print(
                    f"dotfiles-mode: 未知の対象 {args.target!r}（有効な対象: {names}）",
                    file=sys.stderr,
                )
                return 2
            if args.command == "on":
                to_dev = True
            elif args.command == "off":
                to_dev = False
            else:
                cur = item_status(manifest["links_dir"], item)
                to_dev = not cur["dev"]
            return switch_item(
                manifest,
                item,
                to_dev=to_dev,
                no_reload=args.no_reload,
                quiet=args.quiet,
            )
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"dotfiles-mode: {exc}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
