requires = ["github_ssh"]

def public(user, owner):
    root = owner.agent_config_root
    if root.startswith("/") or ".." in root.split("/"):
        fail("agent_links: mutable checkouts must belong to this user's home directory")
    return {"root": user.home + "/" + root}

def user_config(agent_links):
    root = agent_links.root
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

def writes(owner, agent_links, private_repos, secrets):
    # 社用の deploy key で手で clone するときは、agent_config_repo を書かず、自動の clone をさせない（docs/architecture/wsl.md）。
    url = getattr(owner, "agent_config_repo", None)
    if url == None:
        return []
    return [
        write(private_repos, {"url": url, "dest": agent_links.root}),
        write(secrets, private_repos.github_secret),
    ]
