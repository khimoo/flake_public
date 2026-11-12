# 行動: 動画、音楽、写真を見る・聞く・録る。
def writes(gui_apps):
    return [write(gui_apps, app) for app in [
        {"pkg": pkg("vlc")},
        {"pkg": pkg("digikam")},
        {"pkg": pkg("spotify"), "bin": "spotify", "desktop": "spotify.desktop", "mime": ["x-scheme-handler/spotify"], "wayland": True},
        {"pkg": pkg("yt-dlp")},
    ]]

def user_config():
    return {"home": {
        "programs.obs-studio.enable": True,
        "programs.obs-studio.plugins": [pkg("obs-studio-plugins.input-overlay")],
    }}
