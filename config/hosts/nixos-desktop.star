purposes = [
    "xsaved",
    "windows_vm",
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

xsaved_users = {
    "pomu": {
        "data_dir": "/home/pomu/.local/share/xsaved",
        "project_dir": "/home/pomu/.local/share/xsaved-app",
        "database": "xsaved",
        "hsa_override": "10.3.0",
        "web_port": 8765,
        "check_mount": True,
        "backup_repository": "rclone:gdrive:xsaved-backup",
        "backup_password_file": "/home/pomu/.config/xsaved/restic-password",
    },
}
windows_vm_users = ["pomu"]
windows_vm_domain = "win11"
xsaved_proxy = {"user": "pomu", "name": "xsaved.localhost"}
