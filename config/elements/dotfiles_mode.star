# 手段: Neovim・Niri・Quickshell・kanshi・kitty の設定を、既定の Nix store（OFF）と
# ローカル checkout（ON: Dev モード）の間で個別に切り替える仕組み（docs/howtouse/dotfiles-mode.md）。
# switch 時の activation で全対象を Nix store へ戻し、リモート更新時の設定ズレを防ぐ。

def public():
    return {
        "links_rel": ".local/state/dotfiles-mode/links",
    }

def accept(name, label, store, checkout_rel, reload = "none", order = 50):
    return struct(
        name = name,
        label = label,
        store = store,
        checkout_rel = checkout_rel,
        reload = reload,
        order = order,
    )

def user_config(user, checkout, incoming):
    state_dir = user.home + "/.local/state/dotfiles-mode"
    links_dir = state_dir + "/links"
    seen = {}
    raw_items = []
    for w in incoming:
        item = w.value
        name = item.name
        if name in seen:
            fail("dotfiles_mode: duplicate target " + name)
        seen[name] = True
        if item.checkout_rel.startswith("/") or ".." in item.checkout_rel.split("/"):
            fail("dotfiles_mode: checkout_rel must be relative to checkout root: " + item.checkout_rel)
        raw_items.append(item)
    raw_items = sorted(raw_items, key = lambda item: (item.order, item.name))
    items = []
    for item in raw_items:
        items.append({
            "name": item.name,
            "label": item.label,
            "store": item.store,
            "dev": checkout.root + "/" + item.checkout_rel,
            "reload": item.reload,
        })
    manifest = file(
        "dotfiles-mode-manifest.json",
        toJSON({
            "state_dir": state_dir,
            "links_dir": links_dir,
            "items": items,
        }),
    )
    app = shellAppEnv(
        "dotfiles-mode",
        [pkg("python3")],
        {
            "DOTFILES_MODE_MANIFEST": concat(manifest),
        },
        concat('exec python3 "', repoPath("modules/home-manager/dev/dotfiles-mode.py"), '" "$@"\n'),
    )
    act_body = concat(
        'if [ -n "${DRY_RUN_CMD:-}" ]; then\n  ',
        app,
        '/bin/dotfiles-mode sync-store --dry-run\nelse\n  ',
        app,
        '/bin/dotfiles-mode sync-store\nfi\n',
    )
    return {"home": {
        "home.packages": [app],
        "home.activation.dotfilesMode": activation(["writeBoundary"], act_body),
    }}
