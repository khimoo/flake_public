# 目的: git と、その周りの道具（lazygit、delta）。名前とメールは git_identity が入れる。
def user_config():
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
            "git": {"diffRenderers": [{"command": "delta --dark --paging=never", "colorArg": "always"}]},
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
    return {"home": home}
