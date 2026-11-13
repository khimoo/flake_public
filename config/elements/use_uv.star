# 目的: uv で Python のプロジェクトを動かす。
# uv が取得する Python と PyPI の manylinux wheel は Nix の外で作られた実行ファイルなので、nix-ld で動かし、uv には自分で取得した Python だけを使わせる。
# 既定の managed では、取得済みの Python がないと uv は PATH 上の Nix の python3 で venv を作り、その venv では wheel が libstdc++ を見つけられない。
requires = ["nix_ld"]

def user_config():
    return {"home": {
        "programs.uv.enable": True,
        "programs.uv.settings.python-preference": "only-managed",
    }}
