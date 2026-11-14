kind = "machine"
requires = ["x86_64_linux", "nixos_system", "runs_in_wsl", "machine_base", "gui"]

def config():
    return {"nixos_imports": [module("nixos-wsl", "nixosModules.default")], "nixos": {
        "wsl.enable": True,
        "wsl.startMenuLaunchers": True,
    }}
