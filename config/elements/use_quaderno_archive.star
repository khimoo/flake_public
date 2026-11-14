# 手段: 自分用サーバの Quaderno のアーカイブを使う。Quaderno で書いた PDF を、ssh でアーカイブへ送って取り込む（クライアントの側。docs/howtouse/quaderno.md）。
requires = ["find_home_server"]

def writes(quaderno, host, find_home_server):
    return [write(quaderno, {"pull": {
        "ssh": find_home_server.services["serve_quaderno_archive"]["tailnet"],
        "remote_root": getattr(host, "quaderno_remote_root", "Document"),
    }})]
