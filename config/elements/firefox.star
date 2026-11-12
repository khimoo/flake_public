requires = ["gui"]

def public():
    return {"command": exe("firefox", "firefox"), "desktop": "firefox.desktop"}

def config(browser_common):
    extensions = dict(browser_common.extensions)
    extensions.update({
        "treestyletab@piro.sakura.ne.jp": "tree-style-tab",
        "langpack-ja@firefox.mozilla.org": "japanese-language-pack-1",
        "newtaboverride@agenedia.com": "new-tab-override",
    })
    settings = dict(browser_common.settings)
    settings.update({"sidebar.verticalTabs": True})
    return {"home": {
        "programs.firefox.enable": True,
        # XDG の既定パスへの変更には、各マシンの既存プロファイルの手動移動が必要。
        "programs.firefox.configPath": ".mozilla/firefox",
        "programs.firefox.profiles.default": {
            "isDefault": True,
            "settings": settings,
        },
        "programs.firefox.policies.ExtensionSettings": {
            ident: {
                "installation_mode": "normal_installed",
                "install_url": "https://addons.mozilla.org/firefox/downloads/latest/" + slug + "/latest.xpi",
            }
            for ident, slug in extensions.items()
        },
    }}
