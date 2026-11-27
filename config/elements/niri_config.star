# 手段: Niri の生成設定（~/.config/niri/generated.kdl）を組み立てる。
# XKB・環境変数・各機能コンポーネントの寄与（writes）だけを generated.kdl へ集約し、
# 基本の操作・見た目・個人のキーバインドはホーム側の config.kdl（dotfiles-mode 経由）へ寄せる。
requires = ["niri", "terminal_exec"]
needs = ["nixos_system"]

_CONFIG_FILE = "modules/home-manager/gui/niri/config.kdl"

def accept(input = [], binds = [], startup = [], window_rules = [], layer_rules = [], workspaces = [], outputs = [], switch_events = [], environment = {}):
    return struct(input = input, binds = binds, startup = startup, window_rules = window_rules, layer_rules = layer_rules, workspaces = workspaces, outputs = outputs, switch_events = switch_events, environment = environment)

def _quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'

def _xkb(xkb):
    node = "layout " + _quote(xkb.layout)
    if xkb.variant:
        node += "; variant " + _quote(xkb.variant)
    return "keyboard { xkb { " + node + "; }; }"

def _block(name, nodes):
    return name + " {\n" + "".join(["    " + node + "\n" for node in nodes]) + "}\n"

def _generated(xkb, incoming):
    contributions = [w.value for w in incoming]
    binds = []
    environment = {
        "NIXOS_OZONE_WL": "1",
        "XCURSOR_SIZE": "24",
        "XCURSOR_THEME": "Adwaita",
        "XMODIFIERS": "@im=fcitx",
    }
    input_nodes = [_xkb(xkb)]
    startup, window_rules, layer_rules, workspaces, outputs, switch_events = [], [], [], [], [], []
    for value in contributions:
        binds += value.binds
        input_nodes += value.input
        startup += value.startup
        window_rules += value.window_rules
        layer_rules += value.layer_rules
        workspaces += value.workspaces
        outputs += value.outputs
        switch_events += value.switch_events
        for name in sorted(value.environment):
            if name in environment and environment[name] != value.environment[name]:
                fail("niri_config: environment " + name + " is written with different values")
            environment[name] = value.environment[name]
    keys = {}
    for bind in binds:
        key = bind.split(" ")[0]
        if key in keys:
            fail("niri_config: the key " + key + " is bound twice")
        keys[key] = True
    parts = [
        "// このファイルは confgen が生成する（config/elements/niri_config.star）。\n",
        _block("cursor", ['xcursor-theme "Adwaita"', "xcursor-size 24"]),
        # 通知デーモンやシステムトレイから非フォーカスのアプリへフォーカスを移す xdg-activation を許可する。
        _block("debug", ["honor-xdg-activation-with-invalid-serial"]),
        _block("input", input_nodes),
        _block("environment", [name + " " + _quote(environment[name]) for name in sorted(environment)]),
    ]
    if binds:
        parts.append(_block("binds", binds))
    if switch_events:
        parts.append(_block("switch-events", switch_events))
    for argv in startup:
        parts.append("spawn-at-startup " + " ".join([_quote(a) for a in argv]) + "\n")
    for node in workspaces + outputs + window_rules + layer_rules:
        parts.append(node + "\n")
    return "".join(parts)

def config():
    return {"nixos": {
        "environment.systemPackages": [pkg("adwaita-icon-theme")],
    }}

def writes(dotfiles_mode):
    return [write(
        dotfiles_mode,
        name = "niri",
        label = "Niri",
        store = repoPath(_CONFIG_FILE),
        checkout_rel = _CONFIG_FILE,
        reload = "niri",
        order = 10,
    )]

def user_config(user, dotfiles_mode, xkb, incoming):
    return {"home": {
        # 既定は Nix store、Dev モード ON 時だけ checkout を指す（docs/howtouse/dotfiles-mode.md）。
        ("xdg", "configFile", "niri/config.kdl", "source"): outOfStoreLink(user.home + "/" + dotfiles_mode.links_rel + "/niri"),
        ("xdg", "configFile", "niri/generated.kdl", "text"): _generated(xkb, incoming),
    }}
