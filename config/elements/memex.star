# memex（Obsidian の vault）。同期と Obsidian の仕組みは flake input の memex-nix が持ち、
# ここは場所と、目的（memex_sync、obsidian）が書き込んだ選択を渡す。
# vault と memex-nix の clone は、private-repos.nix が local.profile の値から行う。
_VAULT_URL = "git@github.com:khimoo/memex.git"
_SKELETON_URL = "git@github.com:khimoo/memex-nix.git"

def config(user, host, incoming):
    if not host.linux:
        fail("memex: the vault workflow supports Linux only")
    sync = any([w.value.get("sync", False) for w in incoming])
    obsidian = any([w.value.get("obsidian", False) for w in incoming])
    root = user.home + "/sagyo/memex"
    skeleton = user.home + "/sagyo/memex-nix"
    return {
        "home_imports": [module("memex-nix", "homeModules.memex")],
        "home": {
            "local.profile.memexRoot": root,
            "local.profile.memexRepoUrl": _VAULT_URL,
            "local.profile.vaultSkeletonRepo": skeleton,
            "local.profile.vaultSkeletonRepoUrl": _SKELETON_URL,
            "services.memex.enable": True,
            # vault のフォルダは clone が用意する。true にすると clone より先に空のフォルダを作る。
            "services.memex.initializeVault": False,
            "services.memex.vaultDir": root,
            "services.memex.mirrorRepo": skeleton,
            "services.memex.sync.enable": sync,
            "services.memex.sync.autoSync": sync,
            "services.memex.obsidian.enable": obsidian,
        },
    }
