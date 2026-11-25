# 手段: ssh から画面のない Niri のセッションを起動して止める。remote-niri start でセッションと Sunshine を起動し、stop で止める。
# ローカルのセッション（niri.service）が動いているときは起動を断る。同じユーザーの systemd のユーザーマネージャを共有するので、置き換えると画面が消える。
requires = ["niri_config", "sunshine"]
needs = ["nixos_system"]

def config(niri):
    helper = shellApp("remote-niri", [pkg("systemd"), pkg("coreutils")], concat(
        "export XDG_RUNTIME_DIR=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"\n",
        "export DBUS_SESSION_BUS_ADDRESS=\"${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}\"\n",
        "refuse_local() {\n",
        "  case \"$(systemctl --user show -p ActiveState --value niri.service)\" in\n",
        "    inactive|failed) ;;\n",
        "    *) echo 'remote-niri: a local niri session is running or changing state; stop it first.' >&2; exit 1 ;;\n",
        "  esac\n",
        "}\n",
        "case \"${1:-status}\" in\n",
        "  start)\n",
        "    refuse_local\n",
        "    systemctl --user start niri-headless.service\n",
        "    systemctl --user start sunshine.service\n",
        "    ;;\n",
        "  stop)\n",
        "    refuse_local\n",
        "    systemctl --user stop sunshine.service niri-headless.service\n",
        "    ;;\n",
        "  status)\n",
        "    systemctl --user is-active niri-headless.service sunshine.service || true\n",
        "    ;;\n",
        "  *)\n",
        "    echo 'usage: remote-niri start|stop|status' >&2\n",
        "    exit 2\n",
        "    ;;\n",
        "esac\n",
    ))
    return {"nixos": {
        "environment.systemPackages": [helper],
        # niri-session を通らない起動でも、XDG Autostart と終了後のセッションの後始末が要る。
        "systemd.user.services.niri-headless": {
            "description": "Niri compositor without a display (remote streaming)",
            "bindsTo": ["graphical-session.target"],
            "before": ["graphical-session.target", "xdg-desktop-autostart.target"],
            "wants": ["graphical-session-pre.target", "xdg-desktop-autostart.target"],
            "after": ["graphical-session-pre.target"],
            # enableDefaultPath = true のままだと NixOS の最小 PATH がセッションの PATH を上書きし、
            # Niri から spawn するアプリ（kitty 等）が見つからなくなるため無効化する（programs.niri と同じ扱い）。
            "enableDefaultPath": False,
            "environment": {"NIRI_BACKEND": "headless"},
            "postStop": concat(
                exe("systemd", "systemctl"), " --user --no-block start niri-shutdown.target\n",
                exe("systemd", "systemctl"), " --user unset-environment NIRI_SOCKET WAYLAND_DISPLAY DISPLAY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP\n",
            ),
            "serviceConfig": {
                "Slice": "session.slice",
                "Type": "notify",
                "ExecStart": concat(niri.package, "/bin/niri --session"),
                "Restart": "no",
            },
        },
    }}
