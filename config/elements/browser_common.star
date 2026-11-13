def public():
    return {
        "extensions": {
            "{446900e4-71c2-419f-a6a7-df9c091e268b}": "bitwarden-password-manager",
            "{d7742d87-e61d-4b78-b8a1-b469842139fa}": "vimium-ff",
            "clipper@obsidian.md": "web-clipper-obsidian",
            "{da1a7868-5062-4eb9-a787-6d9210703929}": "plamo-translate",
            "enhancerforyoutube@maximerf.addons.mozilla.org": "enhancer-for-youtube",
            "{7058a75b-0f6c-4f10-a54d-bf427dc62b63}": "notebooklmwebimporter",
            "floccus@handmadeideas.org": "floccus",
            "extension@one-tab.com": "onetab",
        },
        "settings": {
            "browser.shell.checkDefaultBrowser": False,
            # 外部の既定ハンドラへ渡すと、ディスパッチャとブラウザの間でループする。
            "network.protocol-handler.expose.http": True,
            "network.protocol-handler.expose.https": True,
            # False では blob: なども外部へ渡され、ダウンロードできなくなる。
            "network.protocol-handler.expose-all": True,
            "intl.locale.requested": "ja,en-US",
            # アドオンと pref は Nix で宣言しているので、Sync で同期しても起動のたびに user.js の値へ戻る。
            "services.sync.engine.addons": False,
            "services.sync.engine.prefs": False,
            # ブックマークは floccus、パスワード、住所、カードは Bitwarden が同期する。
            "services.sync.engine.bookmarks": False,
            "services.sync.engine.passwords": False,
            "services.sync.engine.addresses": False,
            "services.sync.engine.creditcards": False,
            # アドオンの同期を切ると拡張機能の設定の同期も既定で止まるので、設定の同期だけを続ける。
            "services.sync.engine.extension-storage.force": True,
            "signon.rememberSignons": False,
            "extensions.formautofill.addresses.enabled": False,
            "extensions.formautofill.creditCards.enabled": False,
            "browser.tabs.warnOnClose": True,
            "browser.newtabpage.activity-stream.topSitesRows": 4,
            "media.eme.enabled": True,
        },
    }
