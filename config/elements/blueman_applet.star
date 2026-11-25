# 道具: Bluetooth のトレイ アプレットと管理画面 Blueman。
requires = ["bluetooth", "niri_config"]
needs = ["nixos_system"]

def config():
    return {"nixos": {"services.blueman.enable": True}}

def writes(niri_config):
    return [write(niri_config,
        startup = [["blueman-applet"]],
        window_rules = ['window-rule {\n    match app-id="blueman-manager"\n    open-floating true\n}'],
    )]
