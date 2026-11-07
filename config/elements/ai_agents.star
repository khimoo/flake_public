requires = ["agent_links", "agent_sync", "agent_compression"]

_codex = """# このファイルは flake の config/elements/ai_agents.star が生成する。直接編集しないこと。

# サブエージェント (spawn_agent 等のマルチエージェントツール) を無効化する。
[agents]
enabled = false

# `features.multi_agent_v2` が有効になっていると、`agents.enabled = false` よりも優先されます。
# そのため、完全に無効化するには両方の設定をあわせて記述する必要があります。
[features]
multi_agent_v2 = false
"""

def config(host):
    nixos = {}
    if host.linux:
        path = getattr(host, "agent_instructions", None)
        text = _codex
        if path != None:
            instructions = repoText(path)
            # TOML のテーブル見出しより前に置かないと、そのテーブルのキーになる。
            text = concat("developer_instructions = ", toJSON(instructions), "\n", _codex)
            nixos[("environment", "etc", "claude-code/CLAUDE.md", "text")] = instructions
        nixos[("environment", "etc", "codex/config.toml", "text")] = text
    return {"nixos": nixos} if nixos else {}
