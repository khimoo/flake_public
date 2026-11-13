# 行動（趣味、生活管理）: 人と連絡を取る（チャット、メール、ビデオ会議）。
requires = ["temp_storage", "use_ai_agents"]
def writes(gui_apps):
    return [write(gui_apps, app) for app in [
        {"pkg": pkg("discord"), "name": "discord", "bin": "Discord", "desktop": "discord.desktop", "mime": ["x-scheme-handler/discord"], "wayland": True, "autostart": True, "flags": "--start-minimized"},
        {"pkg": pkg("thunderbird"), "name": "thunderbird", "bin": "thunderbird", "desktop": "thunderbird.desktop", "mime": ["x-scheme-handler/mailto", "message/rfc822"], "autostart": True},
        {"pkg": pkg("zoom-us"), "desktop": "Zoom.desktop", "mime": ["x-scheme-handler/zoommtg", "x-scheme-handler/zoomus"]},
    ]]
