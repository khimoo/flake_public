purposes = [
    "minecraft_backup",
    "quaderno",
    "mimikopi",
    "personal_files",
    "ai_agents",
    "dev_tools",
    "daily_editing",
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
    "music_production",
]

echo_cancel_source = "alsa_input.usb-Kingston_HyperX_SoloCast-00.analog-stereo"

lan_ssh = True
private_repos = [
    {"url": "git@github.com:khimoo/llm-wikis.git", "dest": "sagyo/llm-wikis"},
    {"url": "git@github.com:khimoo/xsaved.git", "dest": "sagyo/xsaved"},
]

minecraft_repo = "/mnt/backup/minecraft/repo"
minecraft_remote = "gdrive:minecraft-backups"
quaderno_archive = "/mnt/backup/quaderno"
mimikopi_data_dir = "/home/pomu/.local/share/mimikopi"
mimikopi_hsa_override = "10.3.0"
secrets = [{"secret": "xsaved_restic_password", "path": ".config/xsaved/restic-password"}]
