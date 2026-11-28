# 道具: 音量と画面の明るさの操作（pwvucontrol、wpctl、brightnessctl とそのキー割り当て）。
requires = ["pipewire", "niri_config"]
needs = ["nixos_system"]

_BRIGHTNESS_STEP_SH = """
case "${1:-}" in
    up|down) ;;
    *) exit 2 ;;
esac

# キーを連打しても、直前の書き込みが終わってから実輝度を読む。
exec 9>"${XDG_RUNTIME_DIR:?}/niri-brightness-step.lock"
flock 9

info=$(brightnessctl --class=backlight --machine-readable info)
IFS=, read -r device _ current _ maximum <<< "$info"
target=$current

# 表示用に丸めた % ではなく、機器の実輝度で次の段を探す。
for percent in 0 1 {5..100..5}; do
    level=$(( (maximum * percent + 50) / 100 ))
    if [[ $1 == up ]]; then
        if (( level > current )); then
            target=$level
            break
        fi
    else
        if (( level >= current )); then
            break
        fi
        target=$level
    fi
done

if (( target != current )); then
    brightnessctl --class=backlight --device="$device" --quiet set "$target"
fi
"""

def config():
    step = shellApp("niri-brightness-step", [pkg("brightnessctl"), pkg("util-linux")], _BRIGHTNESS_STEP_SH)
    return {"nixos": {
        "environment.systemPackages": [pkg("pwvucontrol"), pkg("wireplumber"), pkg("brightnessctl"), step],
        "services.udev.packages": [repoPkg("packages/hhkb-bt-audio")],
    }}

def writes(niri_config):
    return [write(niri_config,
        binds = [
            'XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05+ -l 1.0"; }',
            'XF86AudioLowerVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05-"; }',
            'XF86AudioMute allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; }',
            'XF86AudioMicMute allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"; }',
            'XF86MonBrightnessUp allow-when-locked=true { spawn "niri-brightness-step" "up"; }',
            'XF86MonBrightnessDown allow-when-locked=true { spawn "niri-brightness-step" "down"; }',
        ],
        window_rules = ['window-rule {\n    match app-id="pwvucontrol$"\n    open-floating true\n}'],
    )]
