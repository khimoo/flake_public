import json
import subprocess
import sys

# Niri の transform は反時計回り基準のため、時計回り 90° は normal -> 270 -> 180 -> 90 -> normal。
NEXT_CW = {
    "normal": "270",
    "270": "180",
    "180": "90",
    "90": "normal",
    "flipped": "flipped-270",
    "flipped270": "flipped-180",
    "flipped-270": "flipped-180",
    "flipped180": "flipped-90",
    "flipped-180": "flipped-90",
    "flipped90": "flipped",
    "flipped-90": "flipped",
}

LABELS = {
    "normal": "0°（横）",
    "270": "90°（時計回り）",
    "180": "180°（上下反転）",
    "90": "270°（反時計回り 90°）",
}


def run_cmd(argv, check=True):
    return subprocess.run(argv, check=check, capture_output=True, text=True)


def notify(title, body=""):
    cmd = [
        "notify-send",
        "--app-name=niri-rotate",
        "-h",
        "string:x-canonical-private-synchronous:niri-rotate",
        title,
    ]
    if body:
        cmd.append(body)
    run_cmd(cmd, check=False)


def toggle_auto_rotate():
    active = run_cmd(["systemctl", "--user", "is-active", "--quiet", "iio-niri.service"], check=False).returncode == 0
    if active:
        run_cmd(["systemctl", "--user", "stop", "iio-niri.service"])
        notify("画面の自動回転: オフ（固定）")
    else:
        run_cmd(["systemctl", "--user", "start", "iio-niri.service"])
        notify("画面の自動回転: オン")
    return 0


def rotate_cw(output_name):
    run_cmd(["systemctl", "--user", "stop", "iio-niri.service"], check=False)
    outputs = json.loads(run_cmd(["niri", "msg", "--json", "outputs"]).stdout)
    info = outputs.get(output_name)
    if not info or not info.get("logical"):
        print(f"niri-rotate: output {output_name!r} is not active", file=sys.stderr)
        return 1
    current = str(info["logical"].get("transform", "Normal")).lower()
    nxt = NEXT_CW.get(current, "normal")
    run_cmd(["niri", "msg", "output", output_name, "transform", nxt])
    notify("画面を回転", f"{LABELS.get(nxt, nxt)}（自動回転オフ）")
    return 0


def main(argv):
    if len(argv) < 3:
        print("usage: niri-rotate <output> toggle|cw", file=sys.stderr)
        return 2
    output_name, action = argv[1], argv[2]
    if action == "toggle":
        return toggle_auto_rotate()
    if action == "cw":
        return rotate_cw(output_name)
    print(f"niri-rotate: unknown action {action!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
