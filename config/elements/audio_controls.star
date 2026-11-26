# 道具: 音量と画面の明るさの操作（pwvucontrol、wpctl、brightnessctl とそのキー割り当て）。
requires = ["pipewire", "niri_config"]
needs = ["nixos_system"]

def config():
    return {"nixos": {
        "environment.systemPackages": [pkg("pwvucontrol"), pkg("wireplumber"), pkg("brightnessctl")],
        "services.udev.packages": [repoPkg("packages/hhkb-bt-audio")],
    }}

def writes(niri_config):
    return [write(niri_config,
        binds = [
            'XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05+ -l 1.0"; }',
            'XF86AudioLowerVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05-"; }',
            'XF86AudioMute allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; }',
            'XF86AudioMicMute allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"; }',
            'XF86MonBrightnessUp allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "+10%"; }',
            'XF86MonBrightnessDown allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "10%-"; }',
        ],
        window_rules = ['window-rule {\n    match app-id="pwvucontrol$"\n    open-floating true\n}'],
    )]
