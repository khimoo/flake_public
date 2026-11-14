# 手段: git のコミットに、持ち主の名前とメール（持ち主の値 git_username と git_email）を使う。
requires = ["git"]

def user_config(owner):
    return {"home": {
        "programs.git.settings.user.name": owner.git_username,
        "programs.git.settings.user.email": owner.git_email,
    }}
