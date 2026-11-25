requires = ["gui"]

_wayland_flags = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3"

def accept(pkg, desktop = None, mime = [], wayland = False, autostart = False, bin = None, name = None, flags = None):
    if mime and desktop == None:
        fail("mime を既定にするには desktop が要る")
    if wayland and (desktop == None or bin == None):
        fail("wayland = True には desktop と bin が要る")
    if autostart and (name == None or bin == None):
        fail("autostart = True には name と bin が要る")
    if flags != None and not autostart:
        fail("flags は autostart = True のときだけ使う")
    return struct(pkg = pkg, desktop = desktop, mime = mime, wayland = wayland, autostart = autostart, bin = bin, name = name, flags = flags)

def _wayland_desktop(app):
    desktop = app.desktop
    bin_name = app.bin
    return command("modified-" + desktop, concat(
        "cp ", app.pkg, "/share/applications/" + desktop + " $out\n",
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

def _autostart_desktop(app):
    flags = " ".join(([_wayland_flags] if app.wayland else []) + ([app.flags] if app.flags != None else []))
    return concat(
        "[Desktop Entry]\n",
        "Type=Application\n",
        "Name=" + app.name + "\n",
        "Exec=", app.pkg, "/bin/" + app.bin + (" " + flags if flags else "") + "\n",
        "X-GNOME-Autostart-enabled=true\n",
    )

def user_config(incoming):
    apps = [w.value for w in incoming]
    settings = {
        "home.packages": [app.pkg for app in apps],
        "xdg.mimeApps.enable": True,
        # GNOME のスキーム解決には mimeapps.list の既定指定が必要（nixpkgs#301893）。
        "xdg.mimeApps.defaultApplications": {mime: app.desktop for app in apps for mime in app.mime},
    }
    for app in apps:
        if app.wayland:
            settings[("home", "file", ".local/share/applications/" + app.desktop, "source")] = _wayland_desktop(app)
        if app.autostart:
            # systemd.user.services にすると nixos-rebuild switch のたびに sd-switch が介入するため、
            # XDG Autostart でログイン時に 1 回だけ起動する（docs/architecture/default-apps.md）。
            settings[("xdg", "configFile", "autostart/" + app.name + ".desktop", "text")] = _autostart_desktop(app)
    return {"home": settings}
