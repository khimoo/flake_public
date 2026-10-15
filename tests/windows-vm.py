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
    # stop-after があれば、その回数だけ問い合わせられたあとで VM が止まったことにする。
    if [ -f "$VM_DIR/stop-after" ]; then
      left=$(cat "$VM_DIR/stop-after")
      if [ "$left" -le 0 ]; then
        echo "shut off" > "$VM_DIR/state"
        rm "$VM_DIR/stop-after"
      else
        echo $((left - 1)) > "$VM_DIR/stop-after"
      fi
    fi
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
    # lease-after があれば、その回数だけ問い合わせられたあとで late-lease の IP を貸し出したことにする。
    if [ -f "$VM_DIR/lease-after" ]; then
      left=$(cat "$VM_DIR/lease-after")
      if [ "$left" -le 0 ]; then
        cp "$VM_DIR/late-lease" "$VM_DIR/lease"
        rm "$VM_DIR/lease-after"
      else
        echo $((left - 1)) > "$VM_DIR/lease-after"
      fi
    fi
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
    # 実際には FreeRDP が先に終わり、VM はその数十秒後に止まる。RDP_BEHAVIOR=shutdown-later がその順。
    # /args-from:stdin だけを受け取ったときは、FreeRDP と同じく標準入力の一行を一つの引数として読む。
    # freerdp.argv はコマンドライン（ps から見える部分）、freerdp.args は FreeRDP が受け取る引数。
    "sdl-freerdp": """
printf '%s\\n' "$@" > "$VM_DIR/freerdp.argv"
if [ "$*" = /args-from:stdin ]; then
  args=()
  while IFS= read -r line && [ -n "$line" ]; do args+=("$line"); done
  set -- "${args[@]}"
fi
printf '%s\\n' "$@" > "$VM_DIR/freerdp.args"
echo run >> "$VM_DIR/freerdp.runs"
if flock -n "$XDG_RUNTIME_DIR/windows-vm.lock" true; then echo free; else echo held; fi > "$VM_DIR/lock-during-rdp"
if [ -n "${RDP_NESTED-}" ]; then
  status=0
  bash -euo pipefail "$SCRIPT" connect || status=$?
  echo "$status" > "$VM_DIR/nested.status"
fi
if [ "${RDP_BEHAVIOR-}" = poweroff ]; then echo "shut off" > "$VM_DIR/state"; fi
if [ "${RDP_BEHAVIOR-}" = shutdown-later ]; then echo 3 > "$VM_DIR/stop-after"; fi
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
    # GNOME キーリングの代わり。secret-<field> のファイルがあれば、その中身を秘密として返す。
    "secret-tool": """
printf '%s\\n' "$*" >> "$VM_DIR/secret-tool.log"
[ "$1" = lookup ] || exit 99
shift
declare -A attrs
while [ "$#" -ge 2 ]; do attrs[$1]=$2; shift 2; done
[ "${attrs[service]-}" = windows-vm ] && [ "${attrs[vm]-}" = win11 ] || exit 1
secret="$VM_DIR/secret-${attrs[field]-}"
[ -f "$secret" ] || exit 1
cat "$secret"
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
        self.assertNotIn("Windows の起動に時間がかかっています", self.log("notify.log"))

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
        self.assertIn("Windows は起動待機中または接続中です", self.log("notify.log"))
        self.assertNotIn("windows-vm の実行に失敗しました", self.log("notify.log"))

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
        self.assertIn("1 秒待機しても RDP が応答しませんでした", self.log("notify.log"))

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
        self.assertIn("windows-vm の実行に失敗しました", self.log("notify.log"))

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

    def test_waits_for_windows_to_finish_shutting_down_before_reminding(self):
        self.vm_state("running", lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", RDP_BEHAVIOR="shutdown-later", NOTIFY_ACTION="shutdown")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("--action=", self.log("notify.log"))
        self.assertNotIn("shutdown win11", self.log("virsh.log"))

    def test_shutdown_reports_unexpected_failures_as_a_notification(self):
        self.vm_state("running")
        result = self.run_script("shutdown", WINDOWS_VM_DOMAIN="missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("windows-vm の実行に失敗しました", self.log("notify.log"))
        self.assertNotIn("Windows は起動していません", self.log("notify.log"))

    def test_stops_waiting_when_the_vm_stops_during_boot(self):
        self.vm_state("running")
        (self.vm / "stop-after").write_text("3")
        result = self.run_script("connect", WINDOWS_VM_BOOT_TIMEOUT="10")
        self.assertEqual(result.returncode, 1)
        self.assertIn("起動待機中に VM が停止しました（VM の状態: shut off）", self.log("notify.log"))
        self.assertNotIn("RDP が応答しませんでした", self.log("notify.log"))
        self.assertNotIn("windows-vm の実行に失敗しました", self.log("notify.log"))
        self.assertEqual(self.log("freerdp.runs"), "")

    def test_tells_the_user_once_when_boot_takes_long(self):
        self.vm_state("running")
        (self.vm / "late-lease").write_text("127.0.0.1")
        (self.vm / "lease-after").write_text("40")
        self.listen_rdp()
        result = self.run_script("connect", RDP_BEHAVIOR="poweroff", WINDOWS_VM_BOOT_TIMEOUT="60")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log("notify.log").count("Windows の起動に時間がかかっています"), 1)
        self.assertEqual(self.log("freerdp.runs"), "run\n")

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
        self.assertNotIn("windows-vm の実行に失敗しました", self.log("notify.log"))

    def test_signs_in_with_credentials_from_the_keyring(self):
        self.vm_state("running", lease="127.0.0.1")
        (self.vm / "secret-user").write_text("AzureAD\\someone@example.org")
        (self.vm / "secret-password").write_text("pass word;$x")
        self.listen_rdp()
        result = self.run_script("connect", RDP_BEHAVIOR="poweroff")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.log("freerdp.args").split("\n")
        self.assertIn("/u:AzureAD\\someone@example.org", args)
        self.assertIn("/p:pass word;$x", args)
        self.assertEqual(args[0], "/v:127.0.0.1")

    def test_keeps_the_password_off_the_command_line(self):
        self.vm_state("running", lease="127.0.0.1")
        (self.vm / "secret-user").write_text("AzureAD\\someone@example.org")
        (self.vm / "secret-password").write_text("hunter2")
        self.listen_rdp()
        result = self.run_script("connect", RDP_BEHAVIOR="poweroff")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log("freerdp.argv"), "/args-from:stdin\n")
        self.assertIn("/p:hunter2", self.log("freerdp.args"))

    def test_shows_the_sign_in_screen_without_stored_credentials(self):
        self.vm_state("running", lease="127.0.0.1")
        self.listen_rdp()
        result = self.run_script("connect", RDP_BEHAVIOR="poweroff")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log("freerdp.runs"), "run\n")
        self.assertNotIn("/u:", self.log("freerdp.args"))
        self.assertNotIn("/p:", self.log("freerdp.args"))

    # FreeRDP は空の /p: でも自動サインインを試みる。
    def test_sends_no_credentials_when_the_password_is_missing(self):
        self.vm_state("running", lease="127.0.0.1")
        (self.vm / "secret-user").write_text("AzureAD\\someone@example.org")
        self.listen_rdp()
        result = self.run_script("connect", RDP_BEHAVIOR="poweroff")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("/u:", self.log("freerdp.args"))
        self.assertNotIn("/p:", self.log("freerdp.args"))


if __name__ == "__main__":
    unittest.main()
