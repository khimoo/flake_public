def config(incoming):
    parts = []
    for w in incoming:
        if parts:
            parts.append("\n")
        parts.append(w.value)
    if not parts:
        return {}
    return {"home": {"programs.direnv.stdlib": concat(*parts)}}
