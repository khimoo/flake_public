kind = "machine"
requires = ["x86_64_linux", "nixos_system", "runs_in_wsl", "machine_base", "gui", "wsl_default_user"]

def config():
    return {"nixos_imports": [module("nixos-wsl", "nixosModules.default"), repoModule("hosts/nixos-work-wsl/isolation.nix")], "nixos": {
        "wsl.enable": True,
        "wsl.startMenuLaunchers": True,
    }}
