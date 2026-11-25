# 手段: Niri の設定ファイルを組み立てる。ほかの element が accept の項目に値を書き、ここが KDL の節を1つずつにまとめる。
# 全ホストには /etc/niri/config.kdl を置く（Home Manager を使わないユーザーもこれで Niri が動く）。
# Home Manager を使うユーザーは ~/.config/niri/config.kdl（checkout への live symlink）が generated.kdl を include する。
requires = ["niri"]
needs = ["nixos_system"]

def accept(input = [], binds = [], startup = [], window_rules = [], layer_rules = [], workspaces = [], outputs = [], switch_events = [], environment = {}):
    return struct(input = input, binds = binds, startup = startup, window_rules = window_rules, layer_rules = layer_rules, workspaces = workspaces, outputs = outputs, switch_events = switch_events, environment = environment)

# 設定の組み立てで Niri の設定の読み込みが止まらないよう、キーの重複は生成時に止める。
_BASE_BINDS = [
    'Mod+Return { spawn "kitty"; }',
    'Mod+Shift+Slash { show-hotkey-overlay; }',
    'Mod+Q repeat=false { close-window; }',
    'Mod+O repeat=false { toggle-overview; }',
    'Mod+Left { focus-column-left; }',
    'Mod+Right { focus-column-right; }',
    'Mod+Up { focus-window-or-workspace-up; }',
    'Mod+Down { focus-window-or-workspace-down; }',
    'Mod+Ctrl+Left { move-column-left; }',
    'Mod+Ctrl+Right { move-column-right; }',
    'Mod+Ctrl+Up { move-column-to-workspace-up; }',
    'Mod+Ctrl+Down { move-column-to-workspace-down; }',
    'Mod+Page_Up { focus-workspace-up; }',
    'Mod+Page_Down { focus-workspace-down; }',
    'Mod+F { maximize-column; }',
    'Mod+Shift+F { fullscreen-window; }',
    'Mod+V { toggle-window-floating; }',
    'Mod+Alt+V { switch-focus-between-floating-and-tiling; }',
    'Mod+Minus { set-column-width "-10%"; }',
    'Mod+Equal { set-column-width "+10%"; }',
    'Print { screenshot; }',
    'Ctrl+Print { screenshot-screen; }',
    'Alt+Print { screenshot-window; }',
    # Windows VM の FreeRDP がキーボードを掴んでいても、この組み合わせだけは Niri が受ける。
    'Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }',
    'Mod+Shift+E { quit; }',
    'Mod+Shift+P { power-off-monitors; }',
]

# singleton の制限はファイルごとに適用されるので、input は include 先と分けられる。
_SYSTEM_CONFIG = """// このファイルは confgen が生成する（config/elements/niri_config.star）。
// ~/.config/niri/config.kdl があるユーザーには読まれない。
include "/etc/niri/generated.kdl"

prefer-no-csd

layout {
    gaps 8
}

input {
    touchpad {
        tap
        natural-scroll
        dwt
    }
}
"""

def _quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'

def _xkb(host):
    # 素のキーは us と同じで、右 Alt（AltGr）との組み合わせでアクセント付きの文字とデッドキーを打つ。
    # デスクトップの FreeRDP は、右 Alt が AltGr であることを前提に、右 Alt の直後だけキーボードを掴む（docs/architecture/windows-vm.md）。
    layout, _, variant = getattr(host, "xkb_layout", "us").partition("+")
    node = "layout " + _quote(layout)
    if variant:
        node += "; variant " + _quote(variant)
    return "keyboard { xkb { " + node + "; }; }"

def _block(name, nodes):
    return name + " {\n" + "".join(["    " + node + "\n" for node in nodes]) + "}\n"

def _generated(host, incoming):
    contributions = [w.value for w in incoming]
    binds = list(_BASE_BINDS)
    environment = {
        "NIXOS_OZONE_WL": "1",
        "XCURSOR_SIZE": "24",
        "XCURSOR_THEME": "Adwaita",
        "XMODIFIERS": "@im=fcitx",
    }
    input_nodes = [_xkb(host)]
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
        # 通知デーモンや Waybar のシステムトレイから非フォーカスのアプリへフォーカスを移す xdg-activation を許可する。
        _block("debug", ["honor-xdg-activation-with-invalid-serial"]),
        _block("input", input_nodes),
        _block("environment", [name + " " + _quote(environment[name]) for name in sorted(environment)]),
        _block("binds", binds),
    ]
    if switch_events:
        parts.append(_block("switch-events", switch_events))
    for argv in startup:
        parts.append("spawn-at-startup " + " ".join([_quote(a) for a in argv]) + "\n")
    for node in workspaces + outputs + window_rules + layer_rules:
        parts.append(node + "\n")
    return "".join(parts)

def config(host, incoming):
    return {"nixos": {
        "environment.systemPackages": [pkg("kitty"), pkg("adwaita-icon-theme")],
        ("environment", "etc", "niri/config.kdl", "text"): _SYSTEM_CONFIG,
        ("environment", "etc", "niri/generated.kdl", "text"): _generated(host, incoming),
    }}

def user_config(checkout, host, incoming):
    return {"home": {
        # 個人の設定（modules/home-manager/gui/niri/config.kdl）は checkout を直接指す。編集は rebuild なしで反映される。
        ("xdg", "configFile", "niri/config.kdl", "source"): outOfStoreLink(checkout.root + "/modules/home-manager/gui/niri/config.kdl"),
        ("xdg", "configFile", "niri/generated.kdl", "text"): _generated(host, incoming),
    }}
