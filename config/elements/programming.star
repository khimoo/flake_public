# 行動: プログラムを書く。
# xsaved ではなく x_posts を挙げる。xsaved は keep_x_posts を担当する機体でだけ動く（xsaved_for_reference）。
requires = ["web_browsing", "temp_storage", "shell", "git", "daily_editing", "dev_tools", "ai_agents", "task_management", "x_posts"]

def writes(gui_apps):
    return [write(gui_apps, {"pkg": pkg("typst")})]
