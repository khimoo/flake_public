requires = ["pipewire"]

def config(user, host):
    if not host.linux:
        fail("music_production: supports Linux only")
    return {
        "nixos": {
            "musnix.enable": True,
            "musnix.kernel.realtime": False,
            "musnix.rtirq.enable": True,
            "musnix.das_watchdog.enable": True,
            "services.pipewire.jack.enable": True,
            ("services", "pipewire", "extraConfig", "pipewire", "92-low-latency"): {
                "context.properties": {
                    "default.clock.rate": 48000,
                    "default.clock.quantum": 128,
                    "default.clock.min-quantum": 32,
                    "default.clock.max-quantum": 2048,
                },
            },
            ("users", "users", user.name, "extraGroups"): ["audio"],
        },
        "home": {
            "home.packages": [
                repoPkg("packages/jjazzlab"),
                pkg("ardour"),
                pkg("surge-xt"),
                pkg("vital"),
                pkg("helm"),
                pkg("zynaddsubfx"),
                pkg("odin2"),
                pkg("dexed"),
                pkg("geonkick"),
                pkg("drumgizmo"),
                pkg("x42-avldrums"),
                pkg("synthv1"),
                pkg("drumkv1"),
                pkg("musescore"),
                pkg("lilypond"),
                pkg("qpwgraph"),
                pkg("pavucontrol"),
            ],
            ("home", "file", ".lv2", "source"): outOfStoreLink("/etc/profiles/per-user/" + user.name + "/lib/lv2"),
            ("home", "file", ".vst3", "source"): outOfStoreLink("/etc/profiles/per-user/" + user.name + "/lib/vst3"),
            ("home", "file", ".clap", "source"): outOfStoreLink("/etc/profiles/per-user/" + user.name + "/lib/clap"),
            ("home", "file", ".vst", "source"): outOfStoreLink("/etc/profiles/per-user/" + user.name + "/lib/vst"),
            ("home", "file", ".lxvst", "source"): outOfStoreLink("/etc/profiles/per-user/" + user.name + "/lib/lxvst"),
        },
        "nixos_imports": [module("musnix", "nixosModules.musnix")],
    }
