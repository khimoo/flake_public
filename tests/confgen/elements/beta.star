def config():
    return {"nixos_imports": [module("contract", "nixosModules.shared")], "nixos": {
        "test.scalar": 1,
        "test.values": ["beta"],
        "test.ordered": mkAfter(["last"]),
    }}
