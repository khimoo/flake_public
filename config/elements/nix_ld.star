# 目的: Nix の外で作られた実行ファイル（uv が取得する Python、PyPI の manylinux wheel）を動かす。
needs = ["nixos_system"]

def config():
    return {"nixos": {"programs.nix-ld.enable": True}}
