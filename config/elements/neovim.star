# Neovim 本体。機能の要素（nvim_*）が write で渡す道具とデータを集め、Lua が読む
# features.lua（lua/config/nix.lua）を作る。機能の一覧は書き込んだ要素から決まる。
_CONFIG_DIR = "modules/home-manager/dev/neovim/config"

def _merge(data, more):
    # data は {機能: {名前: 値}}。同じ機能の同じ名前を2つの要素が書いたら止める。
    out = {k: dict(v) for k, v in data.items()}
    for feature, values in more.items():
        merged = out.get(feature, {})
        for k, v in values.items():
            if k in merged:
                fail("neovim: two writers set data." + feature + "." + k)
            merged[k] = v
        out[feature] = merged
    return out

def config(checkout, incoming):
    features = []
    packages = []
    lua_packages = []
    data = {}
    for w in incoming:
        name = w.value.get("feature")
        if name:
            features.append(name)
            data = _merge(data, {name: {}})
        for p in w.value.get("packages", []):
            if p not in packages:
                packages.append(p)
        for p in w.value.get("lua_packages", []):
            if p not in lua_packages:
                lua_packages.append(p)
        data = _merge(data, w.value.get("data", {}))
    for name in data:
        if name not in features:
            fail("neovim: data for " + name + ", which no element enables")
    return {"home": {
        "programs.neovim.enable": True,
        "programs.neovim.vimAlias": True,
        "programs.neovim.defaultEditor": True,
        "programs.neovim.withNodeJs": True,
        # home.stateVersion が 26.05 未満のあいだ、Home Manager は従来の既定（true）を使うので明示する。
        "programs.neovim.withRuby": False,
        "programs.neovim.withPython3": False,
        # ~/.config/nvim は checkout への symlink なので、Home Manager の init.lua はその中に置けない。
        "programs.neovim.sideloadInitLua": True,
        "programs.neovim.extraPackages": packages,
        "programs.neovim.extraLuaPackages": luaPackages(lua_packages),
        "programs.neovim.plugins": [pkg("vimPlugins.lazy-nvim")],
        # lua の編集を rebuild なしで反映し、lazy-lock.json を checkout に書き戻すため。
        ("xdg", "configFile", "nvim", "source"): outOfStoreLink(checkout.root + "/" + _CONFIG_DIR),
        ("xdg", "dataFile", "nvim/nix/features.lua", "text"): concat(
            "return ",
            lua({"features": sorted(features), "data": data}),
        ),
        # 一時 markdown draft を nvim で開く。/tmp は systemd-tmpfiles が 10 日で消す。
        "home.shellAliases.draft": 'nvim "$(mktemp --suffix=.md)"',
    }}
