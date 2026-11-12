# 版を固定しているのは x86_64-linux の配布物だけなので、x86_64 の Linux の機体にだけ入れる。
when = ["user_packages", "x86_64_linux"]

def user_config(user):
    return {"home": {"home.packages": [repoPkg(p) for p in getattr(user, "repo_packages", [])]}}
