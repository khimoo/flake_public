# WSL が既定でログインするアカウントは、このホストを管理するアカウント（etc_nixos_link）。
when = ["etc_nixos_link", "runs_in_wsl"]

def user_config(user):
    return {"nixos": {"wsl.defaultUser": user.name}}
