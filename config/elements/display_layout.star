# 道具: ディスプレイの配置（kanshi の既定の組と wdisplays）。接続した出力をすべて有効にするだけの組を置く。出力ごとの配置は /etc/kanshi/config に足す。
requires = ["niri_config"]
needs = ["nixos_system"]

def config():
    return {"nixos": {
        "environment.systemPackages": [pkg("kanshi"), pkg("wdisplays")],
        ("environment", "etc", "kanshi/config", "text"): "profile {\n    output * enable\n}\n",
    }}

def writes(niri_config):
    return [write(niri_config, startup = [["kanshi", "--config", "/etc/kanshi/config"]])]
