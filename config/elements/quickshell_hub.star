# 道具: Quickshell 製の統合スタートメニュー兼通知ハブ（常駐バー無し）。
# 普段は作業ウィンドウのみを表示し、Super 単押し（F24）または Mod+D で
# 左: 6 タブ検索（All / Windows / Files / Clipboard / Vault / Notify + 電卓・Web 検索）
# 右: 時計・電池・ワークスペース・音量・明るさ・システムトレイ・電源ボタン
# を 1 枚のフローティング画面にまとめて開く。通知ポップアップも同じ Quickshell が右上に控えめに出す。
# Home Manager を使わないユーザー（mase）は /etc/xdg/quickshell/hub/ を読み、
# Home Manager を使うユーザーは checkout の live symlink（~/.config/quickshell/hub）を読む。
requires = ["niri_config", "pipewire"]
needs = ["nixos_system"]

_HUB_FILES = [
    "qmldir",
    "Theme.qml",
    "Calc.js",
    "NotificationStore.qml",
    "NotificationPopups.qml",
    "RightColumn.qml",
    "HubWindow.qml",
    "shell.qml",
]

_CLIPHIST_STORE_SH = """set -euo pipefail
sentinel="${XDG_RUNTIME_DIR:-/tmp}/qs-hub-secret-copy"
if [ -f "$sentinel" ]; then
  now=$(date +%s)
  ts=$(cut -d. -f1 "$sentinel" 2>/dev/null || echo 0)
  if [ $((now - ts)) -le 3 ]; then
    cat >/dev/null
    exit 0
  fi
fi
exec cliphist store
"""

_CLIPHIST_COPY_SH = """set -euo pipefail
id="${1:-}"
[ -n "$id" ] || exit 1
printf '%s\\n' "$id" | cliphist decode | wl-copy
"""

_WEB_SEARCH_SH = """set -euo pipefail
query="${1:-}"
[ -n "$query" ] || exit 0
if command -v zen-beta >/dev/null 2>&1; then
  exec zen-beta --search "$query"
fi
encoded=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote_plus(sys.argv[1]))' "$query")
exec xdg-open "https://www.google.com/search?q=${encoded}"
"""

def config(niri):
    vault_script = file("hub-vault.py", repoText("modules/home-manager/gui/quickshell/hub-vault.py"))
    vault_app = shellApp(
        "qs-hub-vault",
        [pkg("python3"), pkg("rbw"), pkg("pinentry-qt"), pkg("wl-clipboard"), pkg("libnotify")],
        concat("exec python3 ", vault_script, ' "$@"\n'),
    )
    clip_store = shellApp(
        "qs-hub-cliphist-store",
        [pkg("cliphist"), pkg("coreutils")],
        _CLIPHIST_STORE_SH,
    )
    clip_copy = shellApp(
        "qs-hub-cliphist-copy",
        [pkg("cliphist"), pkg("wl-clipboard")],
        _CLIPHIST_COPY_SH,
    )
    web_search = shellApp(
        "qs-hub-web-search",
        [pkg("python3"), pkg("xdg-utils")],
        _WEB_SEARCH_SH,
    )

    nixos = {
        # Quickshell の UPower モジュールでバッテリー残量・充電状態を取得する（デスクトップでも無害）。
        "services.upower.enable": True,
        "environment.systemPackages": [
            pkg("quickshell"),
            pkg("cliphist"),
            pkg("wl-clipboard"),
            pkg("fd"),
            pkg("rbw"),
            pkg("pinentry-qt"),
            pkg("brightnessctl"),
            pkg("libnotify"),
            pkg("xdg-utils"),
            pkg("plemoljp-nf"),
            vault_app,
            clip_store,
            clip_copy,
            web_search,
        ],
        "systemd.user.services.quickshell-hub": {
            "description": "Quickshell start menu and notification hub",
            "wantedBy": ["graphical-session.target"],
            "partOf": ["graphical-session.target"],
            "after": ["graphical-session.target"],
            # セッション本来の PATH（zen-beta や per-user パッケージを含む）を上書きしないよう無効化する。
            "enableDefaultPath": False,
            "unitConfig": {"ConditionEnvironment": "WAYLAND_DISPLAY"},
            "serviceConfig": {
                "ExecStart": concat(exe("quickshell", "qs"), " -c hub"),
                "Restart": "on-failure",
                "RestartSec": 2,
            },
        },
        "systemd.user.services.cliphist-watch": {
            "description": "Clipboard history watcher (cliphist)",
            "wantedBy": ["graphical-session.target"],
            "partOf": ["graphical-session.target"],
            "after": ["graphical-session.target"],
            "enableDefaultPath": False,
            "unitConfig": {"ConditionEnvironment": "WAYLAND_DISPLAY"},
            "serviceConfig": {
                "ExecStart": concat(
                    exe("wl-clipboard", "wl-paste"),
                    " --type text --watch ",
                    clip_store,
                    "/bin/qs-hub-cliphist-store",
                ),
                "Restart": "on-failure",
                "RestartSec": 2,
            },
        },
    }
    for name in _HUB_FILES:
        nixos[("environment", "etc", "xdg/quickshell/hub/" + name, "text")] = repoText(
            "modules/home-manager/gui/quickshell/hub/" + name
        )
    # niri は Niri のウィンドウ・ワークスペース・ログアウトをハブから操作するため依存として参照する。
    nixos["environment.systemPackages"].append(niri.package)
    return {"nixos": nixos}

def user_config(checkout):
    return {"home": {
        # 個人の QML は checkout への live symlink。保存した瞬間に Quickshell がホットリロードする。
        ("xdg", "configFile", "quickshell/hub", "source"): outOfStoreLink(
            checkout.root + "/modules/home-manager/gui/quickshell/hub"
        ),
    }}

def writes(niri_config):
    return [write(
        niri_config,
        binds = [
            # keyd が Super 単押しを F24 に変換する。安全策として Mod+D も残す。
            'F24 { spawn "qs" "ipc" "-c" "hub" "call" "hub" "toggle"; }',
            'Mod+D { spawn "qs" "ipc" "-c" "hub" "call" "hub" "toggle"; }',
        ],
        # 画面共有（Zoom / Discord / OBS）中にスタートメニュー（Vault・クリップボード履歴含む）と通知ポップアップが映り込むのを防ぐ。
        layer_rules = [
            'layer-rule {\n    match namespace="^quickshell-hub$"\n    block-out-from "screencast"\n}',
            'layer-rule {\n    match namespace="^quickshell-hub-notifications$"\n    block-out-from "screencast"\n}',
        ],
    )]
