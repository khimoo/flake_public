# Home Manager を使わないユーザーも同じデーモンを使うため、ユニットは NixOS に置く。
requires = ["niri_config"]
needs = ["nixos_system"]

def config():
    return {"nixos": {
        "environment.systemPackages": [pkg("vicinae")],
        "systemd.user.services.vicinae": {
            "description": "Vicinae server daemon",
            "wantedBy": ["graphical-session.target"],
            "partOf": ["graphical-session.target"],
            "after": ["graphical-session.target"],
            # enableDefaultPath = true のままだと NixOS が coreutils 等だけの PATH を Environment= に差し込み、
            # セッション本来の PATH（/etc/profiles/per-user/<user>/bin 等）を上書きしてしまう。
            # zen-beta のように .desktop の Exec= にコマンド名だけを書くアプリを起動できるよう無効化する。
            "enableDefaultPath": False,
            "unitConfig": {"ConditionEnvironment": "WAYLAND_DISPLAY"},
            "serviceConfig": {
                "ExecStart": concat(exe("vicinae", "vicinae"), " server"),
                "Restart": "on-failure",
                "RestartSec": 5,
            },
        },
    }}

def writes(niri_config):
    return [write(niri_config,
        binds = [
            'Mod+D { spawn "vicinae" "toggle"; }',
            'Mod+Shift+V { spawn "vicinae" "vicinae://launch/clipboard/history"; }',
        ],
        # 画面共有（Zoom / Discord / OBS）中にクリップボード履歴などが相手画面へ映り込むのを防ぐ。
        layer_rules = [
            'layer-rule {\n    match namespace="^vicinae$"\n    block-out-from "screencast"\n}',
        ],
    )]

_ENSURE_IMPORT_PY = """import json, pathlib, re, sys
path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
if not path.exists():
    data = {"$schema": "https://vicinae.com/schemas/config.json", "imports": ["./nix.json"]}
    path.write_text(json.dumps(data, indent=2) + "\\n", encoding="utf-8")
    sys.exit(0)
raw = path.read_text(encoding="utf-8")
if '"./nix.json"' in raw:
    sys.exit(0)
# Vicinae の初期 settings.json は // コメントを含む（JSONC）ため、文字列外だけ取り除いて読み込む。
stripped = re.sub(r'"(?:\\\\.|[^"\\\\])*"|//[^\\n]*', lambda m: m.group(0) if m.group(0).startswith('"') else '', raw)
data = json.loads(stripped) if stripped.strip() else {}
imports = data.get("imports")
if not isinstance(imports, list):
    imports = []
if "./nix.json" not in imports:
    imports.insert(0, "./nix.json")
data["imports"] = imports
path.write_text(json.dumps(data, indent=2) + "\\n", encoding="utf-8")
"""

def user_config(user, niri):
    # ~/.config/vicinae/settings.json は GUI からも書き換えられるため直接 symlink せず、
    # Nix 側で管理する項目を nix.json に切り出して imports から読み込む（vicinae 公式推奨）。
    nix_json = concat(
        '''// このファイルは flake_public（config/elements/vicinae.star）が生成する。
// GUI から変更する設定は ~/.config/vicinae/settings.json に保存され、こちらの設定が土台として読み込まれる。
{
  // 外をクリックしたときにランチャーを閉じる。layer-shell の keyboard_interactivity を "on_demand" にしないと効かない。
  "close_on_focus_loss": true,

  // 自動ペーストとスニペット展開を行う vicinae-input-server を無効にする。
  // Wayland の入力隔離を緩める /dev/uinput・/dev/input 権限を与えたくなく、端末（Ctrl+Shift+V）や
  // Neovim での自動ペースト誤爆および Niri 上でのキーマップ乱れ（#994）も避けるため、クリップボード履歴はコピーのみにする。
  "input_server": {
    "enabled": false
  },

  "launcher_window": {
    "layer_shell": {
      "keyboard_interactivity": "on_demand"
    }
  },

  "providers": {
    "power": {
      "entrypoints": {
        "logout": {
          "preferences": {
            // Vicinae 既定の loginctl terminate-session だと systemd --user 配下の niri.service が残り、
            // 再ログイン時に niri-session が "A niri session is already running." で終了して GDM ログインループになる。
            "customProgram": "''', niri.package, '''/bin/niri msg action quit --skip-confirmation"
          }
        }
      }
    }
  }
}
''',
    )
    settings_path = user.home + "/.config/vicinae/settings.json"
    ensure_script = file("ensure-vicinae-import.py", _ENSURE_IMPORT_PY)
    return {"home": {
        ("xdg", "configFile", "vicinae/nix.json", "text"): nix_json,
        "home.activation.vicinaeSettingsImport": activation(
            ["writeBoundary"],
            concat(
                'if [ -z "${DRY_RUN_CMD:-}" ]; then\n  ',
                exe("python3", "python3"), " ", ensure_script, ' "', settings_path, '"\nfi\n',
            ),
        ),
    }}
