requires = ["private_repos"]

# 目的: git と、その周りの道具（lazygit、delta）。名前とメールは config/users/<ユーザー>.toml から。
def config(user, host):
    home = {
        "programs.lazygit.enable": True,
        "programs.lazygit.settings": {
            "gui": {
                "showIcons": True,  # Nerd Font のアイコンを表示する。
                "theme": {
                    "lightTheme": False,
                    "activeBorderColor": ["green", "bold"],
                    "inactiveBorderColor": ["white"],
                },
            },
            # delta を lazygit の中のページャーとして使う。
            "git": {"pagers": [{"pager": "delta --dark --paging=never", "colorArg": "always"}]},
        },
        "programs.git.enable": True,
        "programs.git.lfs.enable": True,
        "programs.git.settings.init.defaultBranch": "main",
        "programs.git.settings.merge.conflictstyle": "zdiff3",
        "programs.delta.enable": True,
        "programs.delta.options": {
            "features": "side-by-side line-numbers decorations",
            "side-by-side": True,
            "line-numbers": True,
            "navigate": True,
            "decorations": {
                "commit-decoration-style": "bold yellow box ul",
                "file-style": "bold yellow ul",
                "file-decoration-style": "none",
            },
        },
    }
    if (hasattr(user, "git_username") or hasattr(user, "git_email")) and getattr(host, "restricted", False):
        fail("restricted host: a git identity in this repository is not allowed (docs/architecture/wsl.md)")
    if hasattr(user, "git_username"):
        home["programs.git.settings.user.name"] = user.git_username
    if hasattr(user, "git_email"):
        home["programs.git.settings.user.email"] = user.git_email
    return {"home": home}
