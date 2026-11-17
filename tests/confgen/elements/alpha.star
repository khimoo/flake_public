def config():
    return {"nixos_imports": [module("contract", "nixosModules.shared")], "nixos": {
        "test.scalar": 1,
        "test.integers": [-9223372036854775808, 9223372036854775807],
        "test.floats": [1000000.0, 0.0000001, -100000000000000000000.0, 1.25e30, 0.0],
        "test.values": ["alpha"],
        "test.literal": '日本語 ${throw "injected"} \\ "\n\t',
        ("test", "names", "key.with.dot"): "literal",
        "test.ordered": mkBefore(["first"]),
    }}

def user_config(user):
    return {"home": {"test.home": user.home}}
