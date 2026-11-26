# 手段: evdev レベルのキーコード変換（keyd）。
# 全ホスト共通の既定キーボード（Super 単押し → F24）を持ち、ホスト固有の差分（内蔵キーボード定義やターボ連打）は writes で受け取る。
needs = ["nixos_system"]

_SUPER_TAP_KEY = "F24"

def public():
    return {"super_tap_key": _SUPER_TAP_KEY}

def accept(extra_keyboards = {}, exclude_default_ids = [], default_layers = {}):
    return struct(
        extra_keyboards = extra_keyboards,
        exclude_default_ids = exclude_default_ids,
        default_layers = default_layers,
    )

def config(incoming):
    excluded = []
    default_settings = {
        "main": {
            "leftmeta": "overload(meta, f24)",
            "rightmeta": "overload(meta, f24)",
        },
    }
    keyboards = {}
    for w in incoming:
        v = w.value
        for dev_id in v.exclude_default_ids:
            if dev_id not in excluded:
                excluded.append(dev_id)
        for layer, binds in v.default_layers.items():
            if layer not in default_settings:
                default_settings[layer] = {}
            for key, action in binds.items():
                if key in default_settings[layer]:
                    fail("keyd: default keyboard key %s.%s is defined twice" % (layer, key))
                default_settings[layer][key] = action
        for name, kb in v.extra_keyboards.items():
            if name == "default" or name in keyboards:
                fail("keyd: keyboard %s is defined twice" % name)
            keyboards[name] = kb
    keyboards["default"] = {
        "ids": ["*"] + ["-" + dev_id for dev_id in excluded],
        "settings": default_settings,
    }
    return {"nixos": {
        "services.keyd": {"enable": True, "keyboards": keyboards},
    }}
