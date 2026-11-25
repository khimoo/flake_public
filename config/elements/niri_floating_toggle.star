# 手段: 現在のワークスペースにあるフローティングウィンドウを一括で隠す／呼び戻す。
# 名前付きワークスペースを常駐させず、一番下の空の動的ワークスペースへ退避するため、戻すと退避先が自動で消える。
requires = ["niri_config"]
needs = ["nixos_system"]

def config(niri):
    script_file = file("niri-toggle-floating.py", repoText("modules/home-manager/gui/niri/toggle-floating.py"))
    helper = shellApp(
        "niri-toggle-floating",
        [pkg("python3"), niri.package],
        concat("exec python3 ", script_file, ' "$@"\n'),
    )
    return {"nixos": {"environment.systemPackages": [helper]}}

def writes(niri_config):
    return [write(niri_config, binds = [
        'Mod+Ctrl+V { spawn "niri-toggle-floating"; }',
    ])]
