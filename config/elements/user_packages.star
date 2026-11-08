# 目的: ユーザーが自分で選んだ repo の中のパッケージ（config/users/<ユーザー>.toml の repo_packages）。
def config(host, user):
    # 版を固定しているのは x86_64-linux の配布物だけなので、macOS には入れない。
    if host.system != "x86_64-linux":
        return {}
    return {"home": {"home.packages": [repoPkg(p) for p in getattr(user, "repo_packages", [])]}}
