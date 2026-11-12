def user_config(incoming):
    parts = []
    for w in incoming:
        if parts:
            parts.append("\n")
        parts.append(w.value)
    home = {
        "programs.direnv.enable": True,
        "programs.direnv.nix-direnv.enable": True,
    }
    if parts:
        home["programs.direnv.stdlib"] = concat(*parts)
    return {"home": home}
