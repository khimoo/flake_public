def public(user):
    root = getattr(user, "agent_config_root", None)
    return {"root": user.home + "/" + root if root != None else None}

def config(user, agent_links):
    root = agent_links.root
    if root == None:
        return {}
    home = {
        "local.profile.agentConfigRoot": root,
        "local.profile.agentConfigRepo": getattr(user, "agent_config_repo", None),
    }
    links = {
        ".claude/CLAUDE.md": "claude/CLAUDE.md",
        ".claude/skills": "shared/skills",
        ".codex/AGENTS.md": "shared/AGENTS.md",
        ".agents/skills": "codex/skills",
        ".codex/rules/base.rules": "codex/rules/base.rules",
        ".codex/agents": "codex/agents",
        ".codex/hooks.json": "codex/hooks.json",
    }
    for directory in ["agents", "commands", "output-styles", "hooks"]:
        links[".claude/" + directory] = "claude/" + directory
    # 設定と履歴を CLI が書き込むため、~/.claude や ~/.codex 全体はリンクにしない。
    for target, source in links.items():
        home[("home", "file", target, "source")] = outOfStoreLink(root + "/" + source)
    return {"home": home}
