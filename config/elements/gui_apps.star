requires = ["gui"]

_wayland_flags = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3"

# 行動の要素が write(gui_apps, アプリ) でアプリを書き込み、gui_apps がまとめて入れる。
# アプリは {"pkg": パッケージ} に、必要なら次を足す。
#   "desktop": desktop ファイル名、"mime": 既定にする MIME の一覧、
#   "wayland": True（Wayland で起動する desktop ファイルを作る。"bin" も要る）、
#   "autostart": True（ログイン時に起動する。"name" と "bin"、必要なら "flags" も要る）。
def _wayland_desktop(app):
    desktop = app["desktop"]
    bin_name = app["bin"]
    return command("modified-" + desktop, concat(
        "cp ", app["pkg"], "/share/applications/" + desktop + " $out\n",
        "if ! grep -q '^Exec=' $out; then\n",
        '  echo "ERROR: No Exec= line found in ' + desktop + '" >&2\n',
        "  exit 1\n",
        "fi\n",
        "sed -i 's|^Exec=.*|Exec=" + bin_name + " " + _wayland_flags + " %U|' $out\n",
        "if ! grep -q '^Exec=" + bin_name + "' $out; then\n",
        '  echo "ERROR: sed replacement failed for ' + desktop + '" >&2\n',
        "  exit 1\n",
        "fi\n",
    ))

def user_config(incoming):
    apps = [w.value for w in incoming]
    settings = {
        "home.packages": [app["pkg"] for app in apps],
        "xdg.mimeApps.enable": True,
        # GNOME のスキーム解決には mimeapps.list の既定指定が必要（nixpkgs#301893）。
        "xdg.mimeApps.defaultApplications": {mime: app["desktop"] for app in apps for mime in app.get("mime", [])},
    }
    for app in apps:
        if app.get("wayland", False):
            settings[("home", "file", ".local/share/applications/" + app["desktop"], "source")] = _wayland_desktop(app)
        if app.get("autostart", False):
            flags = " ".join(([_wayland_flags] if app.get("wayland", False) else []) + ([app["flags"]] if "flags" in app else []))
            settings[("systemd", "user", "services", app["name"])] = {
                "Unit": {
                    "Description": app["name"] + " (autostart)",
                    "After": ["graphical-session.target"],
                    "PartOf": ["graphical-session.target"],
                },
                "Service": {
                    "ExecStart": concat(app["pkg"], "/bin/" + app["bin"] + (" " + flags if flags else "")),
                    "Restart": "on-failure",
                    "RestartSec": 5,
                },
                "Install": {"WantedBy": ["graphical-session.target"]},
            }
    return {"home": settings}
