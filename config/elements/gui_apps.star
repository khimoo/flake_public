requires = ["gui"]

_wayland_flags = "--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3"

# Obsidian は memex が git / claude を含むラッパーを入れるため、素のパッケージを重ねない。
_apps = [
    {"pkg": pkg("slack"), "name": "slack", "bin": "slack", "desktop": "slack.desktop", "mime": ["x-scheme-handler/slack"], "wayland": True, "autostart": True, "flags": "--silent"},
    {"pkg": pkg("discord"), "name": "discord", "bin": "Discord", "desktop": "discord.desktop", "mime": ["x-scheme-handler/discord"], "wayland": True, "autostart": True, "flags": "--start-minimized"},
    {"pkg": pkg("thunderbird"), "name": "thunderbird", "bin": "thunderbird", "desktop": "thunderbird.desktop", "mime": ["x-scheme-handler/mailto", "message/rfc822"], "autostart": True},
    {"pkg": pkg("sticky-notes"), "name": "sticky-notes", "bin": "com.vixalien.sticky", "desktop": "com.vixalien.sticky.desktop", "autostart": True},
    {"pkg": pkg("libreoffice")},
    {"pkg": pkg("pdfarranger"), "desktop": "pdfarranger.desktop", "mime": ["application/pdf"]},
    {"pkg": pkg("bitwarden-desktop")},
    {"pkg": pkg("krita")},
    {"pkg": inputPkg("rnote", "default")},
    {"pkg": pkg("mypaint")},
    {"pkg": pkg("vlc")},
    {"pkg": pkg("xournalpp")},
    # Takeout の日本語ファイル名を保った解凍には p7zip が必要。
    {"pkg": pkg("digikam")},
    {"pkg": pkg("p7zip")},
    {"pkg": pkg("google-chrome")},
    {"pkg": pkg("brave")},
    {"pkg": pkg("spotify"), "bin": "spotify", "desktop": "spotify.desktop", "mime": ["x-scheme-handler/spotify"], "wayland": True},
    {"pkg": pkg("typst")},
    {"pkg": pkg("yt-dlp")},
    {"pkg": pkg("transcribe")},
    {"pkg": pkg("tdf")},
    {"pkg": pkg("vmpk")},
    {"pkg": pkg("showmethekey")},
    {"pkg": pkg("zoom-us"), "desktop": "Zoom.desktop", "mime": ["x-scheme-handler/zoommtg", "x-scheme-handler/zoomus"]},
]

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

def config():
    settings = {
        "home.packages": [app["pkg"] for app in _apps],
        "programs.obs-studio.enable": True,
        "programs.obs-studio.plugins": [pkg("obs-studio-plugins.input-overlay")],
        "programs.foliate.enable": True,
        "programs.anki.enable": True,
        "programs.anki.language": "ja_JP",
        "xdg.mimeApps.enable": True,
        # GNOME のスキーム解決には mimeapps.list の既定指定が必要（nixpkgs#301893）。
        "xdg.mimeApps.defaultApplications": {mime: app["desktop"] for app in _apps for mime in app.get("mime", [])},
    }
    for app in _apps:
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
