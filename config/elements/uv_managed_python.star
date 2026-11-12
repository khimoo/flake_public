# 既定の managed では、取得済みの Python がないと uv は PATH 上の Nix の python3 で venv を作り、
# その venv では wheel が libstdc++ を見つけられない。uv が取得した Python は nix-ld がないと
# 起動しないので、nix-ld のあるホストでだけ設定する（docs/architecture/wsl.md）。
when = ["shell", "nix_ld"]

def user_config():
    return {"home": {"programs.uv.settings.python-preference": "only-managed"}}
