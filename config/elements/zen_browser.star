requires = ["gui"]

# ポリシーは Home Manager モジュールが組み立てたパッケージにだけ入り、入力のパッケージを直接起動すると拡張機能の宣言が適用されない。PATH 上の名前で起動する。
def public():
    return {"command": "zen-beta", "desktop": "zen-beta.desktop"}

# Sine のストアに無い mod の theme.json を、Sine が読む mods.json の項目に直す。
# origin を "store" にすると、sine.allow-unsafe-js を有効にしなくても、この mod の JS だけが読み込まれる。
# no-updates で、Sine 自身の更新機能が Nix の置いたファイルを書き換えないようにする。
_MOD_ENTRY = """. + {
  id: $id,
  enabled: true,
  "no-updates": true,
  origin: "store",
  style: {chrome: (.style.chrome // ""), content: (.style.content // "")}
} | if .readme then .readme |= (split("/") | last) else . end"""

# Sine のストアに無い mod（mods は「mod の ID: ソース」）を、プロファイルの sine-mods に置いて mods.json に登録する。
def _store_less_mods(user, profile, mods):
    mods_dir = user.home + "/.config/zen/" + profile + "/chrome/sine-mods"
    mods_file = mods_dir + "/mods.json"
    jq = exe("jq", "jq")
    home = {}
    body = [
        'if [ -z "${DRY_RUN_CMD:-}" ]; then\n',
        '  mkdir -p "' + mods_dir + '"\n',
        '  [ -f "' + mods_file + '" ] || echo "{}" > "' + mods_file + '"\n',
    ]
    for id, source in mods.items():
        home[("home", "file", ".config/zen/" + profile + "/chrome/sine-mods/" + id)] = {"source": source, "recursive": True}
        body += [
            "  entry=$(", jq, " -c --arg id " + id + " '" + _MOD_ENTRY + "' ", source, "/theme.json)\n",
            "  ", jq, " --argjson e \"$entry\" '.[$e.id] = $e' \"" + mods_file + "\" > \"" + mods_file + ".tmp\"\n",
            '  mv "' + mods_file + '.tmp" "' + mods_file + '"\n',
        ]
    body.append("fi\n")
    # zen-browser-flake の sine.mods の処理（activation の zen-browser-<プロファイル>）も mods.json を書き換えるので、その後に足す。
    home["home.activation.zenStoreLessSineMods"] = activation(["writeBoundary", "zen-browser-" + profile], concat(*body))
    return home

def user_config(user, browser_common):
    settings = dict(browser_common.settings)
    settings.update({
        # ワークスペースとピン留めタブは Sync で同期する。モジュールの spaces と pins は switch のたびに UI での変更を戻すので使わない。
        "services.sync.engine.spaces": True,
        # Zen 独自の文言の日本語訳は半分ほどが英語のままで、誤訳もある。
        "intl.locale.requested": "en-US",
    })
    home = {
        "programs.zen-browser.enable": True,
        "programs.zen-browser.profiles.default": {
            "isDefault": True,
            "settings": settings,
            "sine": {
                "enable": True,
                # Sine のストアにある mod の ID。ストアに無い mod は下の _store_less_mods に書く。
                "mods": ["Zenslop"],
            },
        },
        "programs.zen-browser.policies.ExtensionSettings": {
            ident: {
                "installation_mode": "normal_installed",
                "install_url": "https://addons.mozilla.org/firefox/downloads/latest/" + slug + "/latest.xpi",
            }
            for ident, slug in browser_common.extensions.items()
        },
    }
    home.update(_store_less_mods(user, "default", {
        # Pane（タブの分割と入れ替え）。flake の入力 zen-pane-manager で revision を固定する。
        "zen-pane-manager": pkg("zen-pane-manager"),
    }))
    return {
        "home_imports": [module("zen-browser", "homeModules.beta")],
        "home": home,
    }
