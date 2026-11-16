# 手段: Claude Code を使う。
requires = ["llm_agents", "claude_history", "graphify", "skill_pdf", "plugin_claude_video", "antigravity_cli"]

def user_config():
    return {"home": {"home.packages": [pkg("claude-code")]}}
