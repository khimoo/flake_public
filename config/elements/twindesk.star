requires = ["gui", "bluetooth"]

def config():
    return {
        "nixos_imports": [module("twindesk", "nixosModules.default")],
        "nixos": {
            "programs.twindesk.enable": True,
            "programs.twindesk.package": repoPkgWith("packages/twindesk", {"twindesk": inputPkg("twindesk", "default")}),
        },
    }
