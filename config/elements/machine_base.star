def config(host):
    users = {}
    sudo = []
    for account in host.users:
        name = account["name"]
        admin = account.get("admin", False)
        users[name] = {
            "isNormalUser": True,
            "description": account.get("description", name),
            "extraGroups": account.get("extra_groups", []) + ["networkmanager"] + (["wheel"] if admin else []),
            "shell": pkg(account.get("shell", "bash")),
            "initialPassword": account.get("initial_password"),
            "initialHashedPassword": account.get("initial_hashed_password"),
            "hashedPassword": account.get("hashed_password"),
        }
        if admin:
            sudo.append({"users": [name], "commands": [{"command": "/run/current-system/sw/bin/nixos-rebuild", "options": ["NOPASSWD"]}]})
    locale = getattr(host, "locale", "ja_JP.UTF-8")
    result = {
        "networking.hostName": host.hostname,
        "system.stateVersion": host.state_version,
        "time.timeZone": host.timezone,
        "i18n.defaultLocale": locale,
        "i18n.extraLocaleSettings": {"LC_" + category: locale for category in ["ADDRESS", "IDENTIFICATION", "MEASUREMENT", "MONETARY", "NAME", "NUMERIC", "PAPER", "TELEPHONE", "TIME"]},
        "users.users": users,
        "security.sudo.extraConfig": 'Defaults env_keep += "SSH_AUTH_SOCK"\n',
        "security.sudo.extraRules": sudo,
        "nixpkgs.config.allowUnfree": True,
        "nix.settings.experimental-features": ["nix-command", "flakes"],
        # リモートビルドの一般ユーザーが署名なしの成果物を構築・取り込みできるようにする。
        "nix.settings.trusted-users": ["@wheel"],
        "nix.gc": {"automatic": True, "dates": "weekly", "options": "--delete-older-than 30d"},
        "nix.settings.auto-optimise-store": True,
        "environment.systemPackages": [inputPkg("home-manager", "home-manager")],
    }
    if hasattr(host, "builder"):
        result["nix.settings.max-jobs"] = host.builder["max_jobs"]
        result["nix.settings.system-features"] = host.builder["supported_features"]
    return {"nixos": result}
