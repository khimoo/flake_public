# デスクトップの Windows VM を FreeRDP で使う Implementation Plan

> 履歴: この文書は作成時点の仕様・計画の記録であり、当時の工程指定は現在の必須手順ではありません。現在の指示・手順は [AGENTS.md](../../../AGENTS.md)、[文書整備](../../howtouse/documentation.md)、[検証ガイド](../../howtouse/validation.md) に従います。実装の現状は設定と現在の詳細文書で確認してください。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** nixos-desktop の libvirt VM `win11` を、GNOME のアプリ一覧の「Windows」から起動し、ホストの FreeRDP で表示できるようにする。

**Architecture:** 処理の本体はシェルスクリプト `modules/home-manager/windows-vm.sh` に置き、偽の `virsh`、`sdl-freerdp`、`notify-send`、`virt-manager` を使う Python のテスト（`tests/windows-vm.py`）で動作を確かめる。Home Manager のモジュール `modules/home-manager/windows-vm.nix`（`local.windowsVm`）がそれを `writeShellApplication` で包み、`xdg.desktopEntries` でランチャーを置く。デスクトップだけが `hosts/nixos-desktop/home-manager-pomu.nix` で import して有効にする。

**Tech Stack:** Nix（Home Manager モジュール、`writeShellApplication`）、bash、FreeRDP 3.31.1（`sdl-freerdp`）、libvirt（`virsh`）、libnotify（`notify-send`）、util-linux（`flock`）、Python 3 の unittest。

**Spec:** `docs/superpowers/specs/2026-10-14-windows-vm-rdp-design.md`

## Global Constraints

- `flake_public` は公開 repo。UPN（メールアドレス）、大学名、Kerberos のレルム名、会社 PC のコンピューター名など、個人や所属を特定できる値を書かない。
- `nixos-rebuild`、`home-manager switch` など世代を切り替えるコマンドは実行しない。`nix eval`、`nix build` は使ってよい。
- `bash scripts/check.sh` は実行しない。各タスクに書いた check だけをビルドする。
- Git の flake は未追跡のファイルを読まない。新しいファイルは `git add` してから `nix` で検証する。
- 接続先は `qemu:///system` に固定する。オプションは `enable`、`domain`（既定値なし）、`bootTimeoutSeconds`（既定 180、`ints.positive`）の三つだけにする。
- FreeRDP の引数は `/v:<IP> /sec:tls /dynamic-resolution /network:lan +clipboard /cert:tofu` にする。
- 通知の文言は、Task 1 のスクリプトに書いたものをそのまま使う（テストが文言で判定する）。
- コミットは作業ブランチ `windows-vm-rdp` に積む。メッセージは repo の慣例どおり日本語の Conventional Commits にし、末尾に次の二行を付ける。

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GkUZvDRvr1kSacXEJ42j7d
```

## Review Focus

- 起動中に DHCP のリースが変わる: 古い IP に繋がらなくても待ち続け、新しい IP に接続する。Task 1 の `test_follows_a_lease_that_changes_while_waiting` で確かめる。
- 通知デーモンがない（`notify-send` が失敗する）: 通知が出せなくても接続は進む。Task 1 の `test_connects_even_without_a_notification_daemon`。
- FreeRDP が 0 以外で終わる（認証の失敗や切断）: ロックを外し、VM が動いていれば止め忘れの通知を出す。Task 1 の `test_reminds_even_when_freerdp_fails`。
- 通知のボタンを押す前に、Windows が自分で止まっている: `virsh shutdown` を呼ばず、失敗の通知も出さない。Task 1 の `test_reminder_button_after_windows_already_stopped`。
- VM の名前の書き間違いなど、想定していない失敗: アプリ一覧から起動しても見えるよう、終了時に「windows-vm が失敗しました」と通知する。Task 1 の `test_reports_unexpected_failures_as_a_notification`。

---

## File Structure

- `modules/home-manager/windows-vm.sh`（新規）: ランチャーの本体。`connect`、`shutdown`、`console` の三つのサブコマンドを持つ。設定は環境変数 `WINDOWS_VM_DOMAIN` と `WINDOWS_VM_BOOT_TIMEOUT` から読む。
- `tests/windows-vm.py`（新規）: 偽のコマンドを `PATH` の先頭に置いてスクリプトを動かすテスト。
- `modules/home-manager/windows-vm.nix`（新規）: `local.windowsVm` のオプション、assertion、`windows-vm` のパッケージ、デスクトップエントリ。
- `hosts/nixos-desktop/home-manager-pomu.nix`（変更）: モジュールの import と有効化。
- `tests/default.nix`（変更）: check `windows-vm`（スクリプトのテスト）と `windows-vm-package`（shellcheck を通すビルド）、`module-contracts` の契約。
- `docs/howtouse/windows-vm.md`、`docs/architecture/windows-vm.md`（新規）と、それぞれの `README.md` の目次（変更）。
- `docs/superpowers/specs/2026-10-14-windows-vm-rdp-design.md`（変更）: 状態を実装済みにする。

---

### Task 1: ランチャーのスクリプトと動作テスト

**Files:**
- Create: `tests/windows-vm.py`
- Create: `modules/home-manager/windows-vm.sh`
- Modify: `tests/default.nix`（checks の attrset の末尾、`quaderno-plan` の後ろ）

**Interfaces:**
- Consumes: なし
- Produces: `modules/home-manager/windows-vm.sh`。環境変数 `WINDOWS_VM_DOMAIN`（libvirt のドメイン名）、`WINDOWS_VM_BOOT_TIMEOUT`（秒）、`XDG_RUNTIME_DIR` を読む。`PATH` から `virsh`、`sdl-freerdp`、`notify-send`、`virt-manager`、`flock`、`timeout`、`sleep` を呼ぶ。サブコマンドは `connect`（既定）、`shutdown`、`console`。それ以外は終了コード 2。

- [ ] **Step 1: テストを書く**

`tests/windows-vm.py` を次の内容で作る。

```python
"""Run windows-vm against fake virsh, FreeRDP, notify-send and virt-manager.

libvirt, the VM and the notification daemon are faked. flock, timeout and the
TCP probe are real, so the lock and the wait for RDP behave as on the host.
"""
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

SCRIPT = Path(sys.argv.pop(1)).resolve()

FAKES = {
    "virsh": """
[ "$1 $2" = "-c qemu:///system" ] || { echo "unexpected connection: $1 $2" >&2; exit 99; }
shift 2
printf '%s\\n' "$*" >> "$VM_DIR/virsh.log"
case $1 in
  domstate)
    [ "$2" = win11 ] || { echo "error: failed to get domain '$2'" >&2; exit 1; }
    cat "$VM_DIR/state"
    echo
    ;;
  start)
    echo running > "$VM_DIR/state"
    if [ -f "$VM_DIR/boot-lease" ]; then cp "$VM_DIR/boot-lease" "$VM_DIR/lease"; fi
    ;;
  shutdown)
    [ "$(cat "$VM_DIR/state")" = running ] || { echo "error: domain is not running" >&2; exit 1; }
    echo "shut off" > "$VM_DIR/state"
    ;;
  domifaddr)
    echo ' Name       MAC address          Protocol     Address'
    echo '-------------------------------------------------------------------------------'
    if [ -s "$VM_DIR/lease" ]; then
      echo " vnet0      52:54:00:b6:73:03    ipv4         $(cat "$VM_DIR/lease")/24"
    fi
    echo
    # next-lease があれば、次の問い合わせから DHCP のリースが変わったことにする。
    if [ -f "$VM_DIR/next-lease" ]; then mv "$VM_DIR/next-lease" "$VM_DIR/lease"; fi
    ;;
esac
""",
    # Windows のスタートメニューからのシャットダウンは、RDP_BEHAVIOR=poweroff で VM を止めて表す。
    "sdl-freerdp": """
printf '%s\\n' "$@" > "$VM_DIR/freerdp.args"
echo run >> "$VM_DIR/freerdp.runs"
if flock -n "$XDG_RUNTIME_DIR/windows-vm.lock" true; then echo free; else echo held; fi > "$VM_DIR/lock-during-rdp"
if [ -n "${RDP_NESTED-}" ]; then
  status=0
  bash -euo pipefail "$SCRIPT" connect || status=$?
  echo "$status" > "$VM_DIR/nested.status"
fi
if [ "${RDP_BEHAVIOR-}" = poweroff ]; then echo "shut off" > "$VM_DIR/state"; fi
exit "${RDP_EXIT:-0}"
""",
    # ボタンが押されたときは NOTIFY_ACTION の値を返す。NOTIFY_HOLD_LOCK があれば、
    # ボタンを押す前に別の接続がロックを握った状態を作り、NOTIFY_POWEROFF があれば
    # ボタンを押す前に Windows が止まった状態を作る。NOTIFY_FAIL は通知デーモンがない状態。
    "notify-send": """
printf '%s\\n' "$*" >> "$VM_DIR/notify.log"
if [ -n "${NOTIFY_FAIL-}" ]; then exit 1; fi
case " $* " in
  *" --action="*)
    if [ -n "${NOTIFY_POWEROFF-}" ]; then echo "shut off" > "$VM_DIR/state"; fi
    if [ -n "${NOTIFY_HOLD_LOCK-}" ]; then
      ( exec 8>"$XDG_RUNTIME_DIR/windows-vm.lock"; flock 8; touch "$VM_DIR/held"; exec "$REAL_SLEEP" 30 ) >/dev/null 2>&1 &
      echo $! > "$VM_DIR/holder.pid"
      until [ -e "$VM_DIR/held" ]; do "$REAL_SLEEP" 0.01; done
    fi
    printf '%s\\n' "${NOTIFY_ACTION-}"
    ;;
esac
""",
    "virt-manager": """
printf '%s\\n' "$*" > "$VM_DIR/virt-manager.args"
""",
    # 起動待ちの間隔を縮める。
    "sleep": """
exec "$REAL_SLEEP" 0.01
""",
}


class WindowsVm(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.vm = self.root / "vm"
        self.vm.mkdir()
        runtime = self.root / "runtime"
        runtime.mkdir()
        tools = self.root / "tools"
        tools.mkdir()
        bash = shutil.which("bash")
        for name, body in FAKES.items():
            (tools / name).write_text(f"#!{bash}\nset -euo pipefail\n{body}")
            (tools / name).chmod(0o755)
        self.env = os.environ | {
            "PATH": f"{tools}:{os.environ['PATH']}",
            "WINDOWS_VM_DOMAIN": "win11",
            "WINDOWS_VM_BOOT_TIMEOUT": "5",
            "XDG_RUNTIME_DIR": str(runtime),
            "VM_DIR": str(self.vm),
            "REAL_SLEEP": shutil.which("sleep"),
            "SCRIPT": str(SCRIPT),
        }
        self.addCleanup(self.kill_holder)

    def kill_holder(self):
        pid = self.vm / "holder.pid"
        if pid.exists():
            try:
                os.kill(int(pid.read_text()), 9)
            except ProcessLookupError:
                pass

    def vm_state(self, state, lease=None, boot_lease=None):
        (self.vm / "state").write_text(state + "\n")
        if lease:
            (self.vm / "lease").write_text(lease)
        if boot_lease:
            (self.vm / "boot-lease").write_text(boot_lease)

    def listen_rdp(self):
        server = socket.create_server(("127.0.0.1", 3389))
        server.settimeout(0.05)
        stop = threading.Event()

        def accept():
            while not stop.is_set():
                try:
                    server.accept()[0].close()
                except TimeoutError:
                    pass

        thread = threading.Thread(target=accept)
        thread.start()

        def close():
            stop.set()
            thread.join()
            server.close()

        self.addCleanup(close)

    def run_script(self, *args, **env):
        return subprocess.run(["bash", "-euo", "pipefail", str(SCRIPT), *args],
                              env=self.env | env, capture_output=True, text=True, timeout=60)

    def log(self, name):
        path = self.vm / name
        return path.read_text() if path.exists() else ""

    def test_starts_a_stopped_vm_and_connects_once_rdp_answers(self):
        self.vm_state("shut off", boot_lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", RDP_BEHAVIOR="poweroff")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("start win11\n", self.log("virsh.log"))
        self.assertIn("Windows を起動しています", self.log("notify.log"))
        args = self.log("freerdp.args").split("\n")
        self.assertEqual(args[0], "/v:127.0.0.1")
        for flag in ["/sec:tls", "/dynamic-resolution", "/network:lan", "+clipboard", "/cert:tofu"]:
            self.assertIn(flag, args)
        # Windows ごと止まったので、止め忘れの通知は出さない。
        self.assertNotIn("--action=", self.log("notify.log"))

    def test_connects_to_a_running_vm_without_starting_it(self):
        self.vm_state("running", lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", RDP_BEHAVIOR="poweroff")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("start win11", self.log("virsh.log"))
        self.assertEqual(self.log("freerdp.runs"), "run\n")

    def test_connect_is_the_default_subcommand(self):
        self.vm_state("running", lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script(RDP_BEHAVIOR="poweroff")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log("freerdp.runs"), "run\n")

    def test_holds_the_lock_while_freerdp_runs(self):
        self.vm_state("running", lease="127.0.0.1")
        self.listen_rdp()
        self.run_script("connect", RDP_BEHAVIOR="poweroff")
        self.assertEqual(self.log("lock-during-rdp"), "held\n")

    def test_rejects_a_second_connect_while_connected(self):
        self.vm_state("running", lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", RDP_BEHAVIOR="poweroff", RDP_NESTED="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log("nested.status"), "1\n")
        self.assertEqual(self.log("freerdp.runs"), "run\n")
        self.assertIn("Windows への接続はすでに開いています", self.log("notify.log"))
        self.assertNotIn("windows-vm が失敗しました", self.log("notify.log"))

    def test_reminder_button_shuts_down_a_vm_left_running(self):
        self.vm_state("running", lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", NOTIFY_ACTION="shutdown")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--action=shutdown=シャットダウン", self.log("notify.log"))
        self.assertIn("shutdown win11\n", self.log("virsh.log"))
        self.assertEqual((self.vm / "state").read_text(), "shut off\n")

    def test_dismissed_reminder_leaves_the_vm_running(self):
        self.vm_state("running", lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", NOTIFY_ACTION="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("shutdown win11", self.log("virsh.log"))
        self.assertEqual((self.vm / "state").read_text(), "running\n")

    def test_reminder_button_does_not_stop_a_newer_connection(self):
        self.vm_state("running", lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", NOTIFY_ACTION="shutdown", NOTIFY_HOLD_LOCK="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("shutdown win11", self.log("virsh.log"))
        self.assertIn("別の接続が開いています", self.log("notify.log"))
        self.assertEqual((self.vm / "state").read_text(), "running\n")

    def test_gives_up_when_rdp_never_answers(self):
        self.vm_state("shut off", boot_lease="127.0.0.1")
        result = self.run_script("connect", WINDOWS_VM_BOOT_TIMEOUT="1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.log("freerdp.runs"), "")
        self.assertIn("1 秒待っても RDP が応答しませんでした", self.log("notify.log"))

    def test_gives_up_when_the_vm_gets_no_address(self):
        self.vm_state("shut off")
        self.listen_rdp()
        result = self.run_script("connect", WINDOWS_VM_BOOT_TIMEOUT="1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.log("freerdp.runs"), "")

    def test_refuses_a_vm_in_another_state(self):
        self.vm_state("paused")
        result = self.run_script("connect")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("start win11", self.log("virsh.log"))
        self.assertIn("VM の状態: paused", self.log("notify.log"))
        self.assertEqual(self.log("freerdp.runs"), "")

    def test_reports_unexpected_failures_as_a_notification(self):
        self.vm_state("running")
        result = self.run_script("connect", WINDOWS_VM_DOMAIN="missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("windows-vm が失敗しました", self.log("notify.log"))

    def test_shutdown_requests_acpi_shutdown_of_a_running_vm(self):
        self.vm_state("running")
        result = self.run_script("shutdown")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("shutdown win11\n", self.log("virsh.log"))
        self.assertIn("Windows のシャットダウンを要求しました", self.log("notify.log"))

    def test_shutdown_of_a_stopped_vm_does_nothing(self):
        self.vm_state("shut off")
        result = self.run_script("shutdown")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("shutdown win11", self.log("virsh.log"))
        self.assertIn("Windows は起動していません", self.log("notify.log"))

    def test_console_opens_the_spice_console_in_virt_manager(self):
        self.vm_state("shut off")
        result = self.run_script("console")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log("virt-manager.args"),
                         "--connect qemu:///system --show-domain-console win11\n")

    def test_rejects_an_unknown_subcommand(self):
        result = self.run_script("start")
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage: windows-vm", result.stderr)
        self.assertEqual(self.log("notify.log"), "")

    def test_follows_a_lease_that_changes_while_waiting(self):
        self.vm_state("running", lease="127.0.0.2")
        (self.vm / "next-lease").write_text("127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", RDP_BEHAVIOR="poweroff")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log("freerdp.args").split("\n")[0], "/v:127.0.0.1")

    def test_connects_even_without_a_notification_daemon(self):
        self.vm_state("shut off", boot_lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", RDP_BEHAVIOR="poweroff", NOTIFY_FAIL="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log("freerdp.runs"), "run\n")

    def test_reminds_even_when_freerdp_fails(self):
        self.vm_state("running", lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", RDP_EXIT="131", NOTIFY_ACTION="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--action=shutdown=シャットダウン", self.log("notify.log"))

    def test_reminder_button_after_windows_already_stopped(self):
        self.vm_state("running", lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", NOTIFY_ACTION="shutdown", NOTIFY_POWEROFF="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("shutdown win11", self.log("virsh.log"))
        self.assertNotIn("windows-vm が失敗しました", self.log("notify.log"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: check を足す**

`tests/default.nix` の checks の attrset で、`quaderno-plan = ...;` の定義の直後（attrset を閉じる `}` の前）に次を足す。

```nix
    # windows-vm の起動、待機、ロック、止め忘れの通知を、偽の virsh と FreeRDP で確かめる。
    # flock は util-linux にしかなく、ランチャー自体も Linux 専用なので、Darwin では省く。
    windows-vm =
      if system != "x86_64-linux" then
        pkgs.runCommand "windows-vm-skipped" { } "touch $out"
      else
        pkgs.runCommand "windows-vm" { nativeBuildInputs = [ pkgs.python3 pkgs.util-linux ]; } ''
          python ${./windows-vm.py} ${../modules/home-manager/windows-vm.sh}
          touch "$out"
        '';
```

- [ ] **Step 3: check が失敗することを確かめる**

Run: `git add tests/windows-vm.py tests/default.nix && nix build --no-link -L .#checks.x86_64-linux.windows-vm`
Expected: FAIL。評価の段階で `modules/home-manager/windows-vm.sh` が存在しないというエラー（`path '.../modules/home-manager/windows-vm.sh' does not exist`）になる。

- [ ] **Step 4: スクリプトを書く**

`modules/home-manager/windows-vm.sh` を次の内容で作る。`writeShellApplication` が先頭に shebang と `set -o errexit -o nounset -o pipefail` を足すので、ファイルには書かない（`modules/home-manager/dev/cargo-remote-run.sh` と同じ形）。

```bash
# libvirt の Windows VM を使うときだけ起動し、FreeRDP で表示する。
# 使い方は docs/howtouse/windows-vm.md、設計判断は docs/architecture/windows-vm.md。

domain=$WINDOWS_VM_DOMAIN
boot_timeout=$WINDOWS_VM_BOOT_TIMEOUT
lock=${XDG_RUNTIME_DIR:?}/windows-vm.lock
notified=

virsh() { command virsh -c qemu:///system "$@"; }

notify() { notify-send --app-name=Windows "$@" || true; }

fail() {
  notified=1
  notify "$@"
  exit 1
}

# アプリ一覧から起動すると端末がなく、エラーの出力が見えない。想定外の失敗も通知で知らせる。
on_exit() {
  local status=$?
  if [ "$status" -ne 0 ] && [ -z "$notified" ]; then
    notify "windows-vm が失敗しました" "終了コード $status。端末から windows-vm を実行すると出力を確認できます。"
  fi
}
trap on_exit EXIT

state() { virsh domstate "$domain"; }

address() {
  local proto addr
  while read -r _ _ proto addr; do
    if [ "$proto" = ipv4 ]; then
      echo "${addr%/*}"
      return
    fi
  done < <(virsh domifaddr "$domain" --source lease)
}

reachable() {
  timeout 2 "$BASH" -c ": < /dev/tcp/$1/3389" 2>/dev/null
}

wait_for_rdp() {
  local deadline=$((SECONDS + boot_timeout)) ip
  until ip=$(address) && [ -n "$ip" ] && reachable "$ip"; do
    if [ "$SECONDS" -ge "$deadline" ]; then return 1; fi
    sleep 2
  done
  echo "$ip"
}

request_shutdown() {
  if [ "$(state)" != running ]; then
    notify "Windows は起動していません"
    return
  fi
  virsh shutdown "$domain" >/dev/null
  notify "Windows のシャットダウンを要求しました"
}

# GNOME の通知は一覧に残るので、古い通知のボタンがあとから押されることがある。
# そのとき別の接続が開いていれば（ロックを握れなければ）止めない。
remind() {
  local action
  action=$(notify-send --app-name=Windows --action=shutdown=シャットダウン --wait \
    "Windows はまだ起動しています" "使い終わったらシャットダウンしてください") || return 0
  [ "$action" = shutdown ] || return 0
  exec 9>"$lock"
  if flock -n 9; then
    request_shutdown
  else
    notify "Windows を止めませんでした" "別の接続が開いています"
  fi
}

connect() {
  local current ip
  exec 9>"$lock"
  # 同じ VM に二つ目の RDP 接続を張ると一つ目が切れるので、起動を待つ間から握っておく。
  flock -n 9 || fail "Windows への接続はすでに開いています"
  current=$(state)
  case $current in
    running) ;;
    "shut off")
      virsh start "$domain" >/dev/null
      notify "Windows を起動しています"
      ;;
    *) fail "Windows を起動できません" "VM の状態: $current" ;;
  esac
  ip=$(wait_for_rdp) || fail "Windows に接続できません" "$boot_timeout 秒待っても RDP が応答しませんでした"
  # NLA は切ってある（Entra ID のアカウントでは通らない）。TLS だけで接続し、Windows の画面でサインインする。
  sdl-freerdp "/v:$ip" /sec:tls /dynamic-resolution /network:lan +clipboard /cert:tofu || true
  flock -u 9
  exec 9>&-
  if [ "$(state)" = running ]; then remind; fi
}

case ${1-connect} in
  connect) connect ;;
  shutdown) request_shutdown ;;
  console) exec virt-manager --connect qemu:///system --show-domain-console "$domain" ;;
  *)
    notified=1
    echo "usage: windows-vm [connect|shutdown|console]" >&2
    exit 2
    ;;
esac
```

`reachable` の `-c` の引数をダブルクォートにしているのは、シングルクォートにすると shellcheck が SC2016 を出すため。展開されるのは `virsh` の出力から取り出した IPv4 アドレスだけである。

- [ ] **Step 5: check が通ることを確かめる**

Run: `git add modules/home-manager/windows-vm.sh && nix build --no-link -L .#checks.x86_64-linux.windows-vm`
Expected: PASS。ログの最後に `Ran 20 tests` と `OK` が出る。

- [ ] **Step 6: コミットする**

```bash
git add tests/windows-vm.py tests/default.nix modules/home-manager/windows-vm.sh
git commit -F - <<'EOF'
feat: Windows VM を起動して FreeRDP で接続する windows-vm スクリプトを追加

VM が止まっていれば起動し、RDP が応答するまで待ってから接続する。
FreeRDP を閉じても VM が動いていれば、止め忘れを通知する。

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GkUZvDRvr1kSacXEJ42j7d
EOF
```

---

### Task 2: Home Manager のモジュールとデスクトップでの有効化

**Files:**
- Create: `modules/home-manager/windows-vm.nix`
- Modify: `hosts/nixos-desktop/home-manager-pomu.nix`（`imports` の行と、`local.quaderno` の設定の後ろ）
- Modify: `tests/default.nix`（外側の `let`、`contracts`、checks の attrset）

**Interfaces:**
- Consumes: Task 1 の `modules/home-manager/windows-vm.sh` と、それが読む環境変数 `WINDOWS_VM_DOMAIN`、`WINDOWS_VM_BOOT_TIMEOUT`。
- Produces: オプション `local.windowsVm.enable`（bool）、`local.windowsVm.domain`（str、既定値なし）、`local.windowsVm.bootTimeoutSeconds`（positive int、既定 180）。`home.packages` に名前が `windows-vm` のパッケージ。`xdg.desktopEntries.windows-vm`（actions は `shutdown` と `console`）。

- [ ] **Step 1: 契約とパッケージの check を書く**

`tests/default.nix` の外側の `let` で、`wslSshConfig = ...;` の行の直後に次を足す。

```nix
  desktopUser = inputs.self.nixosConfigurations.nixos-desktop.config.home-manager.users.pomu;
  windowsVm = {
    imports = [ ../modules/home-manager/windows-vm.nix ];
    local.windowsVm = {
      enable = true;
      domain = "win11";
    };
  };
```

`contracts` の中で、`assert rejects { local.quaderno.enable = true; };` の直前に次を足す。

```nix
      # Windows VM のランチャーはデスクトップだけで有効にする。GUI のないユーザーでは評価を止める。
      assert hasLauncher desktopUser "windows-vm";
      assert desktopUser.local.windowsVm.domain == "win11";
      assert rejects windowsVm;
      assert
        system != "x86_64-linux"
        || allAssertions (mkTestHome system [
          windowsVm
          { local.profile.features.gui = true; }
        ]);
```

checks の attrset で、Task 1 で足した `windows-vm = ...;` の直後に次を足す。

```nix
    # windows-vm のビルド（writeShellApplication の shellcheck）を CI で通す。
    # デスクトップの構成は評価しかしないので、ここでビルドしないと見つからない。
    windows-vm-package =
      if system != "x86_64-linux" then
        pkgs.runCommand "windows-vm-package-skipped" { } "touch $out"
      else
        lib.findFirst (p: (p.name or "") == "windows-vm") (throw "windows-vm is not installed")
          (mkTestHome system [
            windowsVm
            { local.profile.features.gui = true; }
          ]).config.home.packages;
```

- [ ] **Step 2: 契約が失敗することを確かめる**

Run: `git add tests/default.nix && nix build --no-link -L .#checks.x86_64-linux.module-contracts`
Expected: FAIL。`modules/home-manager/windows-vm.nix` が存在しないという評価のエラーか、`assert hasLauncher desktopUser "windows-vm";` の失敗（どちらが先に出るかは評価の順による）。

- [ ] **Step 3: モジュールを書く**

`modules/home-manager/windows-vm.nix` を次の内容で作る。

```nix
# libvirt の Windows VM を、使うときだけ起動して FreeRDP で表示する。
#
#   windows-vm connect   止まっていれば起動し、RDP が応答するまで待って接続する（既定）
#   windows-vm shutdown  ACPI のシャットダウンを要求する
#   windows-vm console   USB リダイレクト用に virt-manager で SPICE の画面を開く
#
# VM の Windows でリモートデスクトップを有効にし、NLA を切っておく必要がある。
# 設計判断: docs/architecture/windows-vm.md
# 使い方:   docs/howtouse/windows-vm.md
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.windowsVm;

  windows-vm = pkgs.writeShellApplication {
    name = "windows-vm";
    runtimeInputs = with pkgs; [
      coreutils
      freerdp
      libnotify
      libvirt
      util-linux
      virt-manager
    ];
    runtimeEnv = {
      WINDOWS_VM_DOMAIN = cfg.domain;
      WINDOWS_VM_BOOT_TIMEOUT = toString cfg.bootTimeoutSeconds;
    };
    text = builtins.readFile ./windows-vm.sh;
  };
  launcher = lib.getExe windows-vm;
in
{
  options.local.windowsVm = {
    enable = lib.mkEnableOption "libvirt の Windows VM を FreeRDP で使うランチャー";

    domain = lib.mkOption {
      type = lib.types.str;
      description = ''
        qemu:///system にある VM のドメイン名（`virsh list --all` の Name）。
        VM ごとに違うので既定値は置かず、呼び出し側で指定する。
      '';
    };

    bootTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 180;
      description = ''
        VM を起動してから RDP（3389 番ポート）が応答するまで待つ上限。
        Windows Update の適用で起動が長引き、毎回足りないときに延ばす。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.local.profile.features.gui;
        message = "local.windowsVm: requires local.profile.features.gui (it adds a desktop launcher)";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "local.windowsVm: libvirt and the launcher are supported only on Linux";
      }
    ];

    home.packages = [ windows-vm ];

    xdg.desktopEntries.windows-vm = {
      name = "Windows";
      comment = "VM の Windows を起動して FreeRDP で接続する";
      exec = "${launcher} connect";
      icon = "computer";
      terminal = false;
      categories = [ "System" ];
      actions = {
        shutdown = {
          name = "シャットダウン";
          exec = "${launcher} shutdown";
        };
        console = {
          name = "SPICE で開く";
          exec = "${launcher} console";
        };
      };
    };
  };
}
```

- [ ] **Step 4: デスクトップで有効にする**

`hosts/nixos-desktop/home-manager-pomu.nix` の `imports` の行を次に置き換える。

```nix
  imports = [
    ../../profiles/home/pomu-workstation.nix
    ../../modules/home-manager/minecraft-backup.nix
    ../../modules/home-manager/windows-vm.nix
  ];
```

同じファイルの `local.quaderno = { ... };` の後ろ（`home.packages` の前）に次を足す。

```nix
  # Windows はたまにしか使わないので、VM は常時起動せず、アプリ一覧の「Windows」から起動する。
  # 画面は SPICE ではなく FreeRDP で表示する（docs/architecture/windows-vm.md）。
  local.windowsVm = {
    enable = true;
    domain = "win11";
  };
```

- [ ] **Step 5: 契約とビルドが通ることを確かめる**

Run: `git add modules/home-manager/windows-vm.nix hosts/nixos-desktop/home-manager-pomu.nix && nix build --no-link -L .#checks.x86_64-linux.module-contracts .#checks.x86_64-linux.windows-vm-package .#checks.x86_64-linux.windows-vm`
Expected: PASS（三つともビルドが終わる。`windows-vm-package` のビルドで shellcheck が通る）。

Run: `nix eval --json .#nixosConfigurations.nixos-desktop.config.assertions --apply 'as: map (a: a.message) (builtins.filter (a: !a.assertion) as)'`
Expected: `[]`

Run: `nix eval --raw .#nixosConfigurations.nixos-desktop.config.home-manager.users.pomu.home.activationPackage.drvPath`
Expected: `/nix/store/...-home-manager-generation.drv` の形のパスが出る。

Run: `nix eval --json .#nixosConfigurations.nixos-desktop.config.home-manager.users.pomu.xdg.desktopEntries.windows-vm.actions --apply 'a: builtins.mapAttrs (_: v: v.name) a'`
Expected: `{"console":"SPICE で開く","shutdown":"シャットダウン"}`

- [ ] **Step 6: コミットする**

```bash
git add modules/home-manager/windows-vm.nix hosts/nixos-desktop/home-manager-pomu.nix tests/default.nix
git commit -F - <<'EOF'
feat: デスクトップのアプリ一覧から Windows VM を FreeRDP で開けるようにする

local.windowsVm を追加し、nixos-desktop で有効にした。
右クリックのメニューからシャットダウンと SPICE の画面も開ける。

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GkUZvDRvr1kSacXEJ42j7d
EOF
```

---

### Task 3: ドキュメント

**Files:**
- Create: `docs/howtouse/windows-vm.md`
- Create: `docs/architecture/windows-vm.md`
- Modify: `docs/howtouse/README.md`（目次の表の最後の行の後ろ）
- Modify: `docs/architecture/README.md`（目次の表の最後の行の後ろ）
- Modify: `docs/superpowers/specs/2026-10-14-windows-vm-rdp-design.md`（状態の行）

**Interfaces:**
- Consumes: Task 1 の通知の文言とサブコマンド、Task 2 のオプション名とデスクトップエントリの表示名。
- Produces: なし

- [ ] **Step 1: 使い方の文書を書く**

`docs/howtouse/windows-vm.md` を次の内容で作る。

````markdown
# デスクトップの Windows VM（使い方）

設計判断: [architecture/windows-vm.md](../architecture/windows-vm.md)

実装: [modules/home-manager/windows-vm.nix](../../modules/home-manager/windows-vm.nix)、[modules/home-manager/windows-vm.sh](../../modules/home-manager/windows-vm.sh)

nixos-desktop の libvirt VM は、使うときだけ起動し、画面をホストの FreeRDP で表示します。
VM の名前と起動を待つ上限は、[hosts/nixos-desktop/home-manager-pomu.nix](../../hosts/nixos-desktop/home-manager-pomu.nix) の `local.windowsVm` で指定しています。

## 使う

GNOME のアプリ一覧から「Windows」を開きます。
VM が止まっていれば起動し、RDP が応答するまで待ってから接続します。待っている間は「Windows を起動しています」と通知されます。
Windows のサインイン画面が出たら、パスワードでサインインします。ユーザーを選ぶ画面では「他のユーザー」を選び、メールアドレスの形のユーザー名（UPN）を入力します。

ウィンドウの大きさを変えると、Windows の解像度もそれに合わせて変わります。
ホストと Windows のあいだでは、テキストのコピー＆ペーストができます。

端末から `windows-vm connect` を実行しても同じ動作になり（`connect` は省略できます）、こちらでは FreeRDP の出力を確認できます。

## 終わる

Windows のスタートメニューからシャットダウンします。
Windows が止まると VM も止まり、FreeRDP のウィンドウも閉じます。

FreeRDP のウィンドウだけを閉じると、Windows のセッションは切断された状態で残り、「Windows はまだ起動しています」と通知されます。
通知の「シャットダウン」を押すと VM を止めます。何もしなければ VM は動いたままで、もう一度「Windows」を開けば同じセッションに戻れます。
あとで止めるときは、アプリ一覧の「Windows」を右クリックして「シャットダウン」を選びます。

通知のボタンは、押した時点で別の接続が開いていれば何もしません。古い通知のボタンで、使っている最中の Windows を止めないためです。

シャットダウンは ACPI の電源ボタンを押したのと同じ操作（`virsh shutdown`）なので、保存していない作業が残っていると Windows が止まらないことがあります。
止まらないときは、右クリックの「SPICE で開く」で Windows の画面を確かめます。

## USB を Windows に渡す

USB リダイレクトは SPICE の機能です。
アプリ一覧の「Windows」を右クリックして「SPICE で開く」を選び、virt-manager の画面から USB 機器を渡します。
RDP で接続したままでも渡せます。ただし、Windows は画面を一つのセッションにしか表示しないので、RDP で接続している間は virt-manager 側がロック画面になります。

## 会社 PC とのクリップボード

VM の中の MotionPro から会社 PC に RDP で接続したときは、クリップボードが連携しません。
会社 PC 側はクリップボードを受け付けているので、止めているのは MotionPro が mstsc に渡す接続設定かゲートウェイです。
会社の管理による設定なので、手元で回避しません。

## VM を作り直したとき

Windows で次の二つを設定します。

1. 「設定」→「システム」→「リモート デスクトップ」をオンにする。
2. 同じ画面でオンのスイッチの横を展開し、「ネットワーク レベル認証」を必須にするチェックを外す。

NLA を切る理由は [設計判断](../architecture/windows-vm.md#nla-を切る) にあります。
VM の名前が変わったときは、`local.windowsVm.domain` を合わせます。

## うまくいかないとき

「Windows に接続できません」と通知されたら、待つ上限（既定は 180 秒）のうちに RDP が応答しませんでした。
Windows Update の適用中などで起動が長引いているときは、少し待ってからもう一度開きます。毎回足りないなら `local.windowsVm.bootTimeoutSeconds` を延ばします。
Windows のリモートデスクトップが無効になっている場合も、同じ通知になります。

「Windows への接続はすでに開いています」と通知されたら、別に開いた「Windows」が起動待ちか接続中です。

「windows-vm が失敗しました」と通知されたら、端末から `windows-vm connect` を実行して出力を確かめます。
````

- [ ] **Step 2: 設計判断の文書を書く**

`docs/architecture/windows-vm.md` を次の内容で作る。

````markdown
# デスクトップの Windows VM を FreeRDP で使う

使い方: [howtouse/windows-vm.md](../howtouse/windows-vm.md)

実装: [modules/home-manager/windows-vm.nix](../../modules/home-manager/windows-vm.nix)、[modules/home-manager/windows-vm.sh](../../modules/home-manager/windows-vm.sh)、検証: [tests/windows-vm.py](../../tests/windows-vm.py)

nixos-desktop の libvirt VM（`win11`）は、VM の中の MotionPro（Array Networks の SSL VPN クライアント）と mstsc で会社 PC に接続するときと、たまに Windows を使うときに起動する。
画面は SPICE ではなくホストの FreeRDP から RDP で表示し、VM は使うときだけランチャー（`windows-vm`）で起動する。
以下の観察はいずれも 2026-10-14 のもので、FreeRDP 3.31.1（nixpkgs の `freerdp`。`sdl-freerdp` は SDL3 のクライアント）、QEMU のマシン型 `pc-q35-9.2`、Windows 11 Education（ビルド 26200）で確かめた。

## SPICE ではなく RDP で表示する

VM のビデオは QXL で 3D アクセラレーション（`gl`）は無効、表示は SPICE（virt-manager）だった。
この経路では、VM の中のメモ帳でも打鍵が遅れ、会社 PC への RDP ではさらに遅れた。
VM の Windows でリモートデスクトップを有効にし、ホストの `sdl-freerdp` から接続すると、VM の中と会社 PC の両方で操作感がかなり改善した。
比べたのは体感で、遅延の数値は測っていない。

GPU を VM に渡す案（パススルーや Looking Glass）は、ホストの GPU が RX 6600 の一枚だけなので取れない。
SPICE と QXL の設定を調整する案は、変えられる項目が少なく、RDP に切り替えたほどの効果は見込めないので試していない。

USB リダイレクトは SPICE の機能なので、SPICE の画面は残し、USB を渡すときだけ virt-manager で開く。
SPICE と RDP は同時に接続できる。Windows は画面を一つのセッションにしか出さないので、RDP の接続中は SPICE 側がロック画面になる。

## NLA を切る

VM の Windows には Microsoft Entra ID のアカウントでサインインしている。
NLA を有効にしたままでは、FreeRDP から接続できなかった。

- ユーザー名を `\AzureAD\<UPN>` にすると、FreeRDP は UPN のドメインを Kerberos のレルムとみなして KDC を探し、`Cannot contact any KDC for realm` でタイムアウトした。
- `/auth-pkg-list:!kerberos` を足しても Kerberos を試し、最後は `ERRCONNECT_LOGON_FAILURE` で拒否された。

Microsoft の資料（[Connect to remote Microsoft Entra joined device](https://learn.microsoft.com/en-us/windows/client-management/client-tools/connect-to-remote-aadj-pc)）によると、Entra ID の認証を使わない RDP で Entra ID のアカウントを使うには、接続元と接続先が同じテナントにある必要がある。
ホストの NixOS はテナントに参加していないので、この条件を満たせない。

NLA を切り、`/sec:tls` で接続して Windows のサインイン画面からサインインすると使えた。
代償として、3389 番ポートに届く相手は誰でもサインイン画面まで進める。
この VM は libvirt の `default` ネットワーク（NAT）の内側にあり、届くのはホストと同じネットワークにいる VM だけなので、これを受け入れる。

同じ資料にある Entra ID の認証（mstsc の `enablerdsaadauth`、FreeRDP の `/sec:aad`）は、接続元がテナントに参加していなくても使える。
ただし接続先をホスト名で指定する必要があり、テナントの条件付きアクセスにも左右されるので、試していない。
FreeRDP の `/sec:aad` で接続できると確かめられたら、NLA を戻す。

## 使うときだけ起動する

Windows を使うのは週に数回程度で、VM は動いている間 12 GiB のメモリを確保する（ホストは 32 GiB）。
そのため常時起動はしない。
ランチャーは、VM が止まっていれば起動し、`virsh domifaddr --source lease` で引いた IP の 3389 番ポートが応答するまで待ってから接続する。
終わるときは Windows のスタートメニューからシャットダウンし、VM ごと止める。

退けた案は次の二つ。

- FreeRDP を閉じたら自動で VM をシャットダウンする: 止め忘れはなくなるが、ウィンドウを閉じただけで保存していない作業ごと Windows が終了し、再接続もできなくなる。
- 閉じたら libvirt の managed save で状態を保存し、次回すぐに再開する: 起動待ちはなくなるが、保存先の `/` は空きが 13 GB（使用率 97%）しかなく、最大 12 GiB のメモリの内容を書き込むと埋まりかねない。再開後は VPN の接続も切れているので、再接続の手間は残る。`/` に余裕ができ、起動待ちが気になるようになったら試す。そのときは、virtiofs の共有があっても保存できるかを先に確かめる。

VM の IP は libvirt の DHCP で割り当てられ、変わりうるので、ランチャーは問い合わせのたびに引き直す。
libvirt の NSS モジュールで VM の名前を引けるようにする案は、一つのスクリプトのためにシステムの名前解決を変えることになるので採らない。

## 止め忘れの通知と二重起動

FreeRDP のウィンドウだけを閉じると VM は動いたまま残るので、ランチャーは通知で知らせ、ボタンから止められるようにする。
GNOME の通知は一覧に残るので、古い通知のボタンを後から押すと、そのとき使っている別のセッションの Windows まで止めてしまう。
これを防ぐため、ランチャーは起動を待つ間から FreeRDP が終わるまで `$XDG_RUNTIME_DIR/windows-vm.lock` を `flock` で握り、ボタンの処理はロックを握れたときだけ VM を止める。
同じロックで二重起動も止める。同じ VM に二つ目の RDP 接続を張ると、一つ目が切れるからである。

アプリ一覧から起動すると端末がなく、エラーの出力が見えない。
想定した失敗（VM の状態、起動待ちのタイムアウト、二重起動）は内容を通知し、それ以外の失敗も終了時に通知する。

## 会社 PC との接続で分かったこと

VM の中の mstsc は手元の MotionPro（`127.0.0.1`）に接続し、MotionPro がその通信をトンネルで会社へ送る。
YouTube などの通信はこのトンネルを通らないので、家の回線が速くても、トンネルの速さについては何も分からない。

MotionPro のトンネルのプロトコルを TCP から UDP に変えると、mstsc の接続情報が示す帯域は 460 Kbps から 1.14 Mbps に、RTT は 53 ms から 45 ms になった（それぞれ一回ずつの測定）。
mstsc は手元の MotionPro に TCP で接続するので、接続情報のトランスポートは UDP にしても TCP のまま表示される。
UDP でトンネルを張れたことは、MotionPro のプロセスが外向きの UDP ポートを開いていることで確かめた。
Array Networks の SSL VPN が DTLS（UDP）のトンネルを持つことは、[OpenConnect の資料](https://www.infradead.org/openconnect/array.html) にも書かれている。

会社 PC の RemoteFX のパフォーマンスカウンタの RTT は当てにしない。
従来の mstsc では UDP の RTT が常に 0 になり、TCP の RTT も動かなくなるという報告があり（[Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/109572/remotefx-rtt-performance-counters)）、今回も 3 回とも同じ値だった。
mstsc の接続バーから開く接続情報のほうを使う。

会社 PC とのクリップボードは連携しない。
会社 PC では `fDisableClip` がポリシーに設定されておらず、`WinStations\RDP-Tcp` の値も `0` で、`rdpclip` も動いていた。
止めているのは MotionPro が mstsc に渡す接続設定かゲートウェイで、会社の管理によるものなので回避しない。
````

- [ ] **Step 3: 目次と spec を更新する**

`docs/howtouse/README.md` の目次の表で、`| 会社PCの NixOS-WSL | ...` の行の直後に次の行を足す。

```markdown
| デスクトップの Windows VM | アプリ一覧の「Windows」で VM を起動して FreeRDP で開く。終わり方と止め忘れの通知、USB を渡すときの SPICE、VM を作り直したときの設定 | [windows-vm.md](./windows-vm.md) |
```

`docs/architecture/README.md` の目次の表で、`| [wsl.md](./wsl.md) | ...` の行の直後に次の行を足す。

```markdown
| [windows-vm.md](./windows-vm.md) | デスクトップの Windows VM を SPICE ではなく FreeRDP で表示し、使うときだけ起動する判断。NLA を切る理由（Entra ID のアカウント）、managed save と自動シャットダウンを退けた理由、止め忘れの通知をロックで守る理由、MotionPro のトンネルとクリップボードについて分かったこと |
```

`docs/superpowers/specs/2026-10-14-windows-vm-rdp-design.md` の `状態: 設計（未実装）。` を次に置き換える。

```markdown
状態: 実装済み（2026-10-15）。「未確認」の項目は switch したあとの確認待ち。
```

同じファイルの「確かめ方」で、`extendModules` で確かめると書いた行を次に置き換える（実装では `tests/default.nix` の `rejects` で確かめるため）。

```markdown
- `local.profile.features.gui` を無効にした構成で assertion が評価を止めることを、`tests/default.nix` の契約（`rejects`）で確かめる。
```

- [ ] **Step 4: 文書の検証を通す**

Run: `git add docs/howtouse/windows-vm.md docs/architecture/windows-vm.md && python3 scripts/check-docs.py . && git diff --cached --check && git diff --check`
Expected: 出力なしで終了コード 0。

Run: `grep -rnE '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}' docs/howtouse/windows-vm.md docs/architecture/windows-vm.md modules/home-manager/windows-vm.* tests/windows-vm.py hosts/nixos-desktop/home-manager-pomu.nix || echo clean`
Expected: `clean`

- [ ] **Step 5: コミットする**

```bash
git add docs/howtouse/windows-vm.md docs/architecture/windows-vm.md docs/howtouse/README.md docs/architecture/README.md docs/superpowers/specs/2026-10-14-windows-vm-rdp-design.md
git commit -F - <<'EOF'
docs: デスクトップの Windows VM の使い方と設計判断を追加

FreeRDP で表示する理由、NLA を切る理由、使うときだけ起動する理由と、
MotionPro のトンネルについて分かったことを残す。

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01GkUZvDRvr1kSacXEJ42j7d
EOF
```

---

## switch したあとにご本人が確かめること

このプランの範囲ではビルドと評価までしか確かめられない。switch はご本人が行い、そのあと次を確かめる。

- VM が止まっている状態から「Windows」を開き、起動の通知、サインイン画面、接続までが進む。
- VM が動いている状態から「Windows」を開くと、起動せずにそのまま接続する。
- 接続中にもう一度「Windows」を開くと、「Windows への接続はすでに開いています」と通知される。
- FreeRDP のウィンドウだけを閉じると、「Windows はまだ起動しています」の通知が出て、「シャットダウン」で VM が止まる。
- スタートメニューからシャットダウンすると、VM が止まり、止め忘れの通知は出ない。
- 右クリックの「シャットダウン」と「SPICE で開く」が動く。
- spec の「未確認」の項目（保存していない作業があるときのシャットダウン、GNOME でのアイコンのまとまり、証明書が変わったときの確認、ログの残り方）。
