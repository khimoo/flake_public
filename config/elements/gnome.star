def config():
    return {"nixos": {
        "system.replaceDependencies.replacements": [{
            "oldDependency": pkg("mutter"),
            "newDependency": repoPkg("packages/mutter-transparent-fullscreen"),
        }],
    }, "home": {
        "home.packages": [
            pkg("gnomeExtensions.clipboard-history"),
            pkg("gnomeExtensions.extension-list"),
            pkg("gnomeExtensions.kimpanel"),
            pkg("gnomeExtensions.gsconnect"),
            pkg("gnomeExtensions.paperwm"),
            repoPkg("packages/mic-indicator-visibility-manager"),
        ],
        "dconf.enable": True,
        "dconf.settings": {
            "org/gnome/shell": {
                "disable-user-extensions": False,
                "enabled-extensions": [
                    "clipboard-history@alexsaveau.dev",
                    "extension-list@tu.berry",
                    "kimpanel@kde.org",
                    "gsconnect@andyholmes.github.io",
                    "paperwm@paperwm.github.com",
                    "mic-indicator-visibility-manager@alhaddar.dev",
                ],
            },
            "org/gnome/shell/extensions/mic-indicator-visibility": {
                "show-virtual-sources": True,
                "ignored-properties": ["node.name:echo-cancel-capture", "node.name:echo-cancel-reference"],
            },
            "org/gnome/desktop/interface": {
                "accent-color": "blue",
                "color-scheme": "prefer-dark",
                "show-battery-percentage": True,
                "toolkit-accessibility": False,
            },
        },
        "systemd.user.sessionVariables.NIXOS_OZONE_WL": "1",
    }}
