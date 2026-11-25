# 道具: Quickshell ベースの統合デスクトップシェル DankMaterialShell（nixpkgs の programs.dms-shell）。
# バー、通知、ランチャー、クリップボード履歴、ロック画面、壁紙、音声・明るさ OSD、
# ネットワーク・Bluetooth・トレイ、polkit 認証を一式で担当する。
# Bitwarden 連携として DankVault プラグインと rbw・wl-clipboard・pinentry-qt を同梱する。
requires = ["niri_config", "pipewire"]
needs = ["nixos_system"]

_LOCK_CMD = "dms ipc call lock lock"

def config():
    return {"nixos": {
        "programs.dms-shell": {
            "enable": True,
            "systemd": {
                "enable": True,
                "target": "graphical-session.target",
                "restartIfChanged": True,
            },
            "enableSystemMonitoring": True,
            "enableVPN": True,
            "enableDynamicTheming": True,
            "enableAudioWavelength": True,
            "enableCalendarEvents": False,
            # 自動ペースト（wtype）による端末・Neovim への誤爆を避け、クリップボード履歴はコピーのみにする。
            "enableClipboardPaste": False,
            "plugins": {
                "dankVault": {
                    "enable": True,
                    "src": repoPkg("packages/dank-vault"),
                },
            },
        },
        "environment.systemPackages": [
            pkg("libnotify"),
            pkg("wl-clipboard"),
            pkg("rbw"),
            pkg("pinentry-qt"),
        ],
        # DMS 自身が polkit 認証エージェントを持つため、niri.star 側の polkit-gnome と競合させない。
        "systemd.user.services.polkit-gnome-authentication-agent-1.enable": False,
    }}

def writes(niri_config, swayidle):
    return [
        write(
            niri_config,
            binds = [
                'Mod+D { spawn "dms" "ipc" "call" "spotlight" "toggle"; }',
                'Mod+Shift+V { spawn "dms" "ipc" "call" "clipboard" "toggle"; }',
                'Mod+Alt+L allow-inhibiting=false { spawn "dms" "ipc" "call" "lock" "lock"; }',
                'XF86AudioRaiseVolume allow-when-locked=true { spawn "dms" "ipc" "call" "audio" "increment" "5"; }',
                'XF86AudioLowerVolume allow-when-locked=true { spawn "dms" "ipc" "call" "audio" "decrement" "5"; }',
                'XF86AudioMute allow-when-locked=true { spawn "dms" "ipc" "call" "audio" "mute"; }',
                'XF86AudioMicMute allow-when-locked=true { spawn "dms" "ipc" "call" "audio" "micmute"; }',
                'XF86MonBrightnessUp allow-when-locked=true { spawn "dms" "ipc" "call" "brightness" "increment" "5" ""; }',
                'XF86MonBrightnessDown allow-when-locked=true { spawn "dms" "ipc" "call" "brightness" "decrement" "5" ""; }',
            ],
            # 画面共有（Zoom / Discord / OBS）中に通知ポップアップ、クリップボード履歴、ランチャー（DankVault）が映り込むのを防ぐ。
            layer_rules = [
                'layer-rule {\n    match namespace="^dms:notification-popup$"\n    block-out-from "screencast"\n}',
                'layer-rule {\n    match namespace="^dms:clipboard$"\n    block-out-from "screencast"\n}',
                'layer-rule {\n    match namespace="^dms:spotlight$"\n    block-out-from "screencast"\n}',
            ],
        ),
        write(swayidle, lock_command = _LOCK_CMD, lock_packages = [pkg("dms-shell")]),
    ]
