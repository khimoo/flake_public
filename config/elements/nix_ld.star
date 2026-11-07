# 目的: Nix の外で作られた実行ファイル（uv が取得する Python、PyPI の manylinux wheel）を動かす。
def config():
    return {"nixos": {"programs.nix-ld.enable": True}}
