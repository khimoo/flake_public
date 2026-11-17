# 利用目的（趣味、生活管理）: 人と連絡を取る（Slack、Discord、メール、ビデオ会議）。
requires = ["slack", "temp_storage", "use_ai_agents"]
def writes(gui_apps):
    return [
        write(gui_apps, pkg = pkg("discord"), name = "discord", bin = "Discord", desktop = "discord.desktop", mime = ["x-scheme-handler/discord"], wayland = True, autostart = True, flags = "--start-minimized"),
        write(gui_apps, pkg = pkg("thunderbird"), name = "thunderbird", bin = "thunderbird", desktop = "thunderbird.desktop", mime = ["x-scheme-handler/mailto", "message/rfc822"], autostart = True),
        write(gui_apps, pkg = pkg("zoom-us"), desktop = "Zoom.desktop", mime = ["x-scheme-handler/zoommtg", "x-scheme-handler/zoomus"]),
    ]
