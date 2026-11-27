requires = ["gui"]

_wayland_flags = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3"

def accept(pkg, desktop = None, mime = [], wayland = False, autostart = False, bin = None, name = None, flags = None, restore_id = None, session_restore = None):
    if mime and desktop == None:
        fail("mime を既定にするには desktop が要る")
    if wayland and (desktop == None or bin == None):
        fail("wayland = True には desktop と bin が要る")
    if autostart and (name == None or bin == None):
        fail("autostart = True には name と bin が要る")
    if flags != None and not autostart:
        fail("flags は autostart = True のときだけ使う")
    if restore_id != None and not autostart:
        fail("restore_id は autostart = True のときだけ使う")
    return struct(pkg = pkg, desktop = desktop, mime = mime, wayland = wayland, autostart = autostart, bin = bin, name = name, flags = flags, restore_id = restore_id, session_restore = session_restore)

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

def _autostart_command(app):
    flags = " ".join(([_wayland_flags] if app.wayland else []) + ([app.flags] if app.flags != None else []))
    return concat(app.pkg, "/bin/" + app.bin + (" " + flags if flags else ""))

def _autostart_desktop(app, launch):
    return concat(
        "[Desktop Entry]\n",
        "Type=Application\n",
        "Name=" + app.name + "\n",
        "Exec=", launch, "\n",
        "X-GNOME-Autostart-enabled=true\n",
    )

def _restore_unit(restore, fallback):
    config_file = file("nirinit-config.toml", concat(
        "[skip]\napps = [" + ", ".join(['"' + app_id + '"' for app_id in restore.session_restore]) + "]\n[launch]\n",
        *[concat('"' + app.restore_id + '" = "', _autostart_command(app), '"\n') for app in fallback]
    ))
    launcher = script("nirinit-session", concat(
        # nirinit が保存を始める前に app_id だけを読み、保存にないアプリを通常の配置で起動する。
        'snapshot="${XDG_DATA_HOME:-$HOME/.local/share}/nirinit/session.json"\n',
        'saved_ids=$(', exe("jq", "jq"), ' -ce \'map(select(.launch_command | type == "string") | .app_id | strings)\' "$snapshot" 2>/dev/null) || saved_ids=\'[]\'\n',
        *[concat(
            'if ! ', exe("jq", "jq"), ' -e --arg app "' + app.restore_id + '" \'index($app) != null\' <<< "$saved_ids" >/dev/null; then\n',
            "    niri msg action spawn -- ", _autostart_command(app), "\nfi\n",
        ) for app in fallback] + [concat("exec ", restore.pkg, "/bin/nirinit --save-interval 30 --config ", config_file, "\n")]
    ))
    # HM の sd-switch で復元を再実行せず、ローカルの Niri がソケットを公開したログイン時だけ起動する。
    return file("nirinit.service", concat(
        "[Unit]\nDescription=Restore and save the local Niri session\n",
        "After=niri.service\nRequisite=niri.service\nPartOf=niri.service\nConditionEnvironment=NIRI_SOCKET\n",
        "[Service]\nUMask=0077\nExecStart=", launcher, "\n",
    ))

def _autostart_outside_local_niri(app):
    # niri.<wayland>.<pid>.sock の PID がローカルの niri.service と一致するときだけ nirinit に任せる。
    launcher = script("autostart-" + app.name, concat(
        'pid=$("', exe("systemd", "systemctl"), '" --user show niri.service -p MainPID --value)\n',
        'if [ "${pid:-0}" -gt 0 ]; then\n',
        '    case "${NIRI_SOCKET:-}" in */niri.*."$pid".sock) exit 0 ;; esac\n',
        "fi\n",
        "exec ", _autostart_command(app), "\n",
    ))
    return launcher

def user_config(incoming):
    apps = [w.value for w in incoming if w.value.session_restore == None]
    restore = [w.value for w in incoming if w.value.session_restore != None]
    if len(restore) > 1:
        fail("gui_apps: session_restore は一つだけ設定できる")
    settings = {
        "home.packages": [app.pkg for app in apps],
        "xdg.mimeApps.enable": True,
        # GNOME のスキーム解決には mimeapps.list の既定指定が必要（nixpkgs#301893）。
        "xdg.mimeApps.defaultApplications": {mime: app.desktop for app in apps for mime in app.mime},
    }
    if restore:
        fallback = [app for app in apps if app.restore_id != None]
        unit = _restore_unit(restore[0], fallback)
        settings["home.packages"] += [restore[0].pkg]
        settings[("xdg", "configFile", "systemd/user/nirinit.service", "source")] = unit
        settings[("xdg", "configFile", "systemd/user/niri.service.d/30-nirinit.conf", "text")] = "[Unit]\nWants=nirinit.service\n"
    for app in apps:
        if app.wayland:
            settings[("home", "file", ".local/share/applications/" + app.desktop, "source")] = _wayland_desktop(app)
        if app.autostart:
            # systemd.user.services にすると nixos-rebuild switch のたびに sd-switch が介入するため、
            # XDG Autostart でログイン時に 1 回だけ起動する（docs/architecture/default-apps.md）。
            launch = _autostart_outside_local_niri(app) if restore and app.restore_id != None else _autostart_command(app)
            settings[("xdg", "configFile", "autostart/" + app.name + ".desktop", "text")] = _autostart_desktop(app, launch)
    return {"home": settings}
