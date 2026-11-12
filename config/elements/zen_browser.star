requires = ["gui"]

# ポリシーは Home Manager モジュールが組み立てたパッケージにだけ入り、入力のパッケージを直接起動すると拡張機能の宣言が適用されない。PATH 上の名前で起動する。
def public():
    return {"command": "zen-beta", "desktop": "zen-beta.desktop"}

def config(browser_common):
    settings = dict(browser_common.settings)
    settings.update({
        # ワークスペースとピン留めタブは Sync で同期する。モジュールの spaces と pins は switch のたびに UI での変更を戻すので使わない。
        "services.sync.engine.spaces": True,
        # Zen 独自の文言の日本語訳は半分ほどが英語のままで、誤訳もある。
        "intl.locale.requested": "en-US",
    })
    return {
        "home_imports": [module("zen-browser", "homeModules.beta")],
        "home": {
            "programs.zen-browser.enable": True,
            "programs.zen-browser.profiles.default": {
                "isDefault": True,
                "settings": settings,
            },
            "programs.zen-browser.policies.ExtensionSettings": {
                ident: {
                    "installation_mode": "normal_installed",
                    "install_url": "https://addons.mozilla.org/firefox/downloads/latest/" + slug + "/latest.xpi",
                }
                for ident, slug in browser_common.extensions.items()
            },
        },
    }
