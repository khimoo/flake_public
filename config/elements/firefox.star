requires = ["gui"]

def public():
    return {"command": exe("firefox", "firefox"), "desktop": "firefox.desktop"}

def config():
    extensions = {
        "{77fcd6fa-22a1-498c-88a5-cee7bf16b989}": "manaba-plus",
        "jid1-YcMV6ngYmQRA2w@jetpack": "pinterest",
        "@firefoxinvertcolors": "invert-colors",
        "side-view@mozilla.org": "side-view",
        "{d7742d87-e61d-4b78-b8a1-b469842139fa}": "vimium-ff",
        "clipper@obsidian.md": "web-clipper-obsidian",
        "enhancerforyoutube@maximerf.addons.mozilla.org": "enhancer-for-youtube",
        "{7058a75b-0f6c-4f10-a54d-bf427dc62b63}": "notebooklmwebimporter",
        "newtaboverride@agenedia.com": "new-tab-override",
        "{54e2eb33-18eb-46ad-a4e4-1329c29f6e17}": "block-website",
        "uBlock0@raymondhill.net": "ublock-origin",
        "treestyletab@piro.sakura.ne.jp": "tree-style-tab",
        "soundlift@yourdomain.com": "soundlift-volume-booster",
        "extension@one-tab.com": "onetab",
        "floccus@handmadeideas.org": "floccus",
        "{da1a7868-5062-4eb9-a787-6d9210703929}": "plamo-translate",
        "langpack-ja@firefox.mozilla.org": "japanese-language-pack-1",
        "{446900e4-71c2-419f-a6a7-df9c091e268b}": "bitwarden-password-manager",
    }
    return {"home": {
        "programs.firefox.enable": True,
        # XDG の既定パスへの変更には、各マシンの既存プロファイルの手動移動が必要。
        "programs.firefox.configPath": ".mozilla/firefox",
        "programs.firefox.profiles.default": {
            "isDefault": True,
            "settings": {
                "browser.shell.checkDefaultBrowser": False,
                # 外部の既定ハンドラへ渡すと、ディスパッチャと Firefox の間でループする。
                "network.protocol-handler.expose.http": True,
                "network.protocol-handler.expose.https": True,
                # False では blob: なども外部へ渡され、ダウンロードできなくなる。
                "network.protocol-handler.expose-all": True,
            },
        },
        "programs.firefox.policies.ExtensionSettings": {
            ident: {
                "installation_mode": "normal_installed",
                "install_url": "https://addons.mozilla.org/firefox/downloads/latest/" + slug + "/latest.xpi",
            }
            for ident, slug in extensions.items()
        },
    }}
