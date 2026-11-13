# 手段: Claude Code を使う。
requires = ["claude_history", "happy", "graphify"]

def user_config():
    return {"home": {"home.packages": [pkg("claude-code")]}}
