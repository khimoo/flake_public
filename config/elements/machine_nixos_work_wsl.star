kind = "machine"
requires = ["x86_64_linux", "nixos_system", "downloaded_dev_binaries", "company_isolated", "machine_base", "gui"]

def config(host):
    return {"nixos_imports": [module("nixos-wsl", "nixosModules.default")], "nixos": {
        "wsl.enable": True,
        "wsl.defaultUser": host.users[0]["name"],
        "wsl.startMenuLaunchers": True,
    }}
