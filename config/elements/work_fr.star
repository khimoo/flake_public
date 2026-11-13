# 行動: fr の仕事（Slack）。
requires = ["web_browsing", "task_management"]
def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("slack"), "name": "slack", "bin": "slack", "desktop": "slack.desktop", "mime": ["x-scheme-handler/slack"], "wayland": True, "autostart": True, "flags": "--silent"})]
