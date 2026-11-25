# 道具: ステータスバー Waybar。/etc/xdg/waybar に既定を置き、Home Manager を使うユーザーには checkout の個人設定を live symlink で渡す。
requires = ["niri_config"]
needs = ["nixos_system"]

def config():
    return {"nixos": {
        "environment.systemPackages": [pkg("waybar")],
        "fonts.packages": [pkg("plemoljp-nf")],
        ("environment", "etc", "xdg/waybar/config.jsonc", "text"): repoText("modules/home-manager/gui/waybar/config.jsonc"),
        ("environment", "etc", "xdg/waybar/style.css", "text"): repoText("modules/home-manager/gui/waybar/style.css"),
    }}

def writes(niri_config):
    return [write(niri_config, startup = [["waybar"]])]

def user_config(checkout):
    return {"home": {
        ("xdg", "configFile", "waybar/config.jsonc", "source"): outOfStoreLink(checkout.root + "/modules/home-manager/gui/waybar/config.jsonc"),
        ("xdg", "configFile", "waybar/style.css", "source"): outOfStoreLink(checkout.root + "/modules/home-manager/gui/waybar/style.css"),
    }}
