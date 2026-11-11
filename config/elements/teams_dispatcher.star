requires = ["gui"]

def writes(web_browsing):
    return [write(web_browsing, "teams-url-dispatcher.desktop")]

def config(web_browsing):
    dispatcher = scriptBin("teams-url-dispatcher", concat(
        'case "$1" in\n',
        '  *teams.microsoft.com*|*teams.live.com*)\n',
        '    exec ', exe("junction", "re.sonny.Junction"), ' "$1" ;;\n',
        '  *)\n',
        '    exec ', web_browsing.command, ' "$1" ;;\n',
        'esac\n',
    ))
    settings = {
        "home.packages": [pkg("junction"), pkg("teams-for-linux")],
        # 同じアイコンのアカウントを区別するため、Junction にアプリ名を表示させる。
        "dconf.settings": {"re/sonny/Junction": {"show-app-names": True}},
        ("home", "file", ".local/share/applications/teams-url-dispatcher.desktop", "text"): concat(
            "[Desktop Entry]\n",
            "Name=Teams URL Dispatcher\n",
            "Comment=Route Teams URLs to Junction, others to the default browser\n",
            "Exec=", dispatcher, "/bin/teams-url-dispatcher %U\n",
            "Type=Application\n",
            "NoDisplay=true\n",
            "MimeType=x-scheme-handler/http;x-scheme-handler/https;\n",
        ),
    }
    # 同梱 desktop と同名にして、メニューの重複を防ぐ。
    accounts = [("for-linux", "Teams", ""), ("uni", "Teams (Uni)", " --partition=uni")]
    for ident, label, flags in accounts:
        settings[("home", "file", ".local/share/applications/teams-" + ident + ".desktop", "text")] = concat(
            "[Desktop Entry]\n",
            "Name=" + label + "\n",
            "Comment=Microsoft Teams - " + label + "\n",
            "Exec=", exe("teams-for-linux", "teams-for-linux"), flags + " %U\n",
            "Icon=teams-for-linux\n",
            "Type=Application\n",
            "Categories=Network;Chat;\n",
            "Terminal=false\n",
            "StartupWMClass=teams-for-linux\n",
            # Junction の候補に出すために両スキームを宣言する。既定はディスパッチャを使う。
            "MimeType=x-scheme-handler/https;x-scheme-handler/http;\n",
        )
    return {"home": settings}
