purposes = ["personal_files", 
    "ai_agents",
    "alook_open",
    "cargo_remote_run",
    "dev_tools",
    "daily_editing",
    "sshfs_editing",
    "memex_sync",
    "obsidian",
    "shell",
    "git",
    "gui",
    "gnome",
    "japanese_input",
    "desktop",
    "printing",
    "bluetooth",
    "sns_block",
    "call_audio",
]

echo_cancel_source = "alsa_input.platform-avs_dmic.19.auto.stereo-fallback"

alook_open_remotes = {
    "desktop-local": "desktop",
    "desktop-ts": "desktop-ts",
}
cargo_remote_run_host = "desktop-ts"

agent_instructions = "hosts/nixos-spin713/agent-instructions.md"

lan_ssh = True
private_repos = [{"url": "git@github.com:khimoo/llm-wikis.git", "dest": "sagyo/llm-wikis"}]
