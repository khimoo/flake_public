def public(user):
    return {"root": user.home + "/" + getattr(user, "flake_root", "sagyo/flake_public")}
