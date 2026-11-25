# 道具: スクロール型タイル式の Wayland コンポジタ Niri。仮想出力（Sunshine の拡張ディスプレイ）に要る PR #3800 を取り込んだ版を使う。
needs = ["nixos_system"]

def public():
    return {"package": repoPkg("packages/niri-virtual-outputs")}

# XDG Autostart（gui_apps と twindesk の desktop ファイル）は、niri.service が Wants する xdg-desktop-autostart.target を
# systemd が実行する。dex を足すと同じアプリが二重に起動するので入れない。
def config():
    return {"nixos": {
        "programs.niri.enable": True,
        "programs.niri.package": repoPkg("packages/niri-virtual-outputs"),
        # X11 のアプリを動かす。programs.niri は Xwayland を用意しない。
        "environment.systemPackages": [pkg("xwayland-satellite")],
        # 画面共有の portal（xdg-desktop-portal-gnome）が使う Secret Service と、Windows VM の認証情報の保管先。
        "services.gnome.gnome-keyring.enable": True,
        # polkit の認証画面を出すエージェント。polkit 本体は programs.niri が有効にするが、エージェントは入らない。
        "systemd.user.services.polkit-gnome-authentication-agent-1": {
            "description": "polkit authentication agent",
            "wantedBy": ["graphical-session.target"],
            "wants": ["graphical-session.target"],
            "after": ["graphical-session.target"],
            "serviceConfig": {
                "Type": "simple",
                "ExecStart": concat(pkg("polkit_gnome"), "/libexec/polkit-gnome-authentication-agent-1"),
                "Restart": "on-failure",
                "RestartSec": 1,
                "TimeoutStopSec": 10,
            },
        },
    }}
