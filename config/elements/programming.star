# 行動（趣味）: プログラムを書く。
# xsaved（サーバ）ではなく x_posts を挙げる。サーバは自分用サーバの機体でだけ動き、ほかの機体は xsaved_client で接続する。
requires = ["web_browsing", "temp_storage", "shell", "git", "daily_editing", "dev_tools", "task_management", "use_xsaved", "use_ai_agents"]

def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("typst")})]
