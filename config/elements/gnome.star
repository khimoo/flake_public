requires = ["gui"]

def config():
    return {"nixos": {
        "system.replaceDependencies.replacements": [{
            "oldDependency": pkg("mutter"),
            "newDependency": repoPkg("packages/mutter-transparent-fullscreen"),
        }],
    }}

def user_config(host):
    result = {"home": {
        "home.packages": [
            pkg("gnomeExtensions.clipboard-history"),
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
    interface = result["home"]["dconf.settings"]["org/gnome/desktop/interface"]
    if hasattr(host, "text_scaling_factor"):
        interface["text-scaling-factor"] = host.text_scaling_factor
    if hasattr(host, "xkb_layout"):
        # 素のキーは us と同じで、右 Alt（AltGr）との組み合わせでアクセント付きの文字とデッドキーを打つ。
        # デスクトップの FreeRDP は、右 Alt が AltGr であることを前提に、右 Alt の直後だけキーボードを掴む（docs/architecture/windows-vm.md）。
        result["home"]["dconf.settings"]["org/gnome/desktop/input-sources"] = {"sources": [gvariantTuple(["xkb", host.xkb_layout])]}
    return result
