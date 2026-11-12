def public(user):
    root = getattr(user, "agent_config_root", None)
    if root != None and (root.startswith("/") or ".." in root.split("/")):
        fail("agent_links: mutable checkouts must belong to this user's home directory")
    return {"root": user.home + "/" + root if root != None else None}

def user_config(agent_links):
    root = agent_links.root
    if root == None:
        fail("agent_links: set agent_config_root in config/users/<user>.toml")
    home = {}
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

def writes(user, agent_links, private_repos, secrets):
    url = getattr(user, "agent_config_repo", None)
    if url != None and agent_links.root == None:
        fail("agent_links: a clone URL requires its corresponding checkout path")
    if agent_links.root == None or url == None:
        return []
    return [
        write(private_repos, {"url": url, "dest": agent_links.root}),
        write(secrets, private_repos.github_secret),
    ]
