# 手段: 端末を開くときに使う端末を1か所で決める。
# xdg-terminal-exec（freedesktop に提案中の Default Terminal Execution Specification の実装）が
# /etc/xdg/xdg-terminals.list に並べた端末を開く。Niri の Mod+Return と、Quickshell ハブが
# .desktop の Terminal=true のアプリ（yazi・btop など）を起動するときに、これを呼ぶ。
# 端末を替えるときは、この element の package と desktop ファイル名だけを直す。
needs = ["nixos_system"]

def config():
    return {"nixos": {
        "xdg.terminal-exec.enable": True,
        "xdg.terminal-exec.settings": {"default": ["kitty.desktop"]},
        # Home Manager を使わないユーザー（mase）も同じ端末を開けるよう、システムに入れる。
        # kitty の設定（フォント・kitten）は kitty.star が Home Manager のユーザーにだけ置く。
        "environment.systemPackages": [pkg("kitty")],
    }}
