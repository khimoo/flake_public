def user_config(user):
    home = {}
    modes = getattr(user, "agent_compression", {})
    allowed = {
        "caveman": ["off", "lite", "full", "ultra", "wenyan-lite", "wenyan", "wenyan-full", "wenyan-ultra"],
        "genshijin": ["off", "polite", "normal", "extreme"],
    }
    for name, mode in modes.items():
        if name not in allowed:
            fail("unknown agent compression plugin: " + name)
        if mode != None:
            if mode not in allowed[name]:
                fail("invalid agent compression mode for " + name + ": " + mode)
            home[("xdg", "configFile", name + "/config.json", "text")] = concat(toJSON({"defaultMode": mode}), "\n")
    if not home:
        fail("agent_compression: set agent_compression in config/users/<user>.toml")
    return {"home": home}
