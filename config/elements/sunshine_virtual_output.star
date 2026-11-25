# 配信アプリの終了時に仮想出力を消し、次の接続でクライアントの解像度を使えるようにする。
needs = ["nixos_system"]

def config():
    return {"nixos": {"services.sunshine.settings.output_name": "sunshine-extend"}}

def writes(sunshine, niri):
    cli = concat(niri.package, "/bin/niri")
    prepare = script("sunshine-extend-prepare", concat(
        "set -eu\n",
        # 前回の切断が異常終了だったときの残りを消してから作る。
        cli, " msg remove-virtual-output sunshine-extend >/dev/null 2>&1 || true\n",
        "exec ", cli, ' msg create-virtual-output --name sunshine-extend --width "${SUNSHINE_CLIENT_WIDTH:-1920}" --height "${SUNSHINE_CLIENT_HEIGHT:-1080}" --refresh-rate "${SUNSHINE_CLIENT_FPS:-60}"\n',
    ))
    cleanup = script("sunshine-extend-cleanup", concat(cli, " msg remove-virtual-output sunshine-extend || true\n"))
    return [write(sunshine, app = {
        "name": "Extend (Virtual Display)",
        "prep-cmd": [{"do": concat(prepare), "undo": concat(cleanup)}],
        "auto-detach": "true",
    })]
