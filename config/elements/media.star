# 利用目的（趣味）: 動画、音楽、写真を見る・聞く。
requires = ["temp_storage", "use_ai_agents"]
def writes(gui_apps):
    return [
        write(gui_apps, pkg = pkg("vlc")),
        write(gui_apps, pkg = pkg("digikam")),
        write(gui_apps, pkg = pkg("spotify"), bin = "spotify", desktop = "spotify.desktop", mime = ["x-scheme-handler/spotify"], wayland = True),
        write(gui_apps, pkg = pkg("yt-dlp")),
    ]
