# 道具: 通知デーモン swaync（SwayNotificationCenter）。
# 設定は /etc/xdg/swaync/config.json に置き、Niri のセッション開始時に起動する。
# 通知の左クリックで既定の操作を実行し、Waybar のアイコンから通知履歴パネル（Control Center）を開閉する。
requires = ["niri_config"]
needs = ["nixos_system"]

_CONFIG_JSON = """{
  "positionX": "right",
  "positionY": "top",
  "control-center-positionX": "right",
  "control-center-positionY": "top",
  "layer": "overlay",
  "control-center-layer": "top",
  "layer-shell": true,
  "timeout": 8,
  "timeout-low": 5,
  "timeout-critical": 0,
  "hide-on-clear": true,
  "hide-on-action": true,
  "notification-2fa-action": true,
  "notification-inline-replies": false,
  "widgets": [
    "title",
    "dnd",
    "notifications"
  ],
  "widget-config": {
    "title": {
      "text": "Notifications",
      "clear-all-button": true,
      "button-text": "Clear All"
    },
    "dnd": {
      "text": "Do Not Disturb"
    }
  }
}
"""

def config():
    return {"nixos": {
        "environment.systemPackages": [pkg("swaynotificationcenter"), pkg("libnotify")],
        ("environment", "etc", "xdg/swaync/config.json", "text"): _CONFIG_JSON,
    }}

def writes(niri_config):
    return [write(
        niri_config,
        startup = [["swaync", "--config", "/etc/xdg/swaync/config.json"]],
        # 画面共有（Zoom / Discord / OBS）中に通知ポップアップや通知履歴が映り込むのを防ぐ。
        layer_rules = [
            'layer-rule {\n    match namespace="^swaync-notification-window$"\n    block-out-from "screencast"\n}',
            'layer-rule {\n    match namespace="^swaync-control-center$"\n    block-out-from "screencast"\n}',
        ],
    )]
