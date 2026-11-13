# 手段: Claude Code を使う。
requires = ["claude_history", "happy", "graphify", "skill_pdf", "plugin_claude_video"]

def user_config():
    return {"home": {"home.packages": [pkg("claude-code")]}}
