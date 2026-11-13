# 目的: 端末での作業。bash と、その上で使う CLI の道具。
requires = ["yazi", "nix_index"]

def user_config():
    return {"home": {
        "home.packages": [
            pkg("curl"),
            pkg("fastfetch"),
            pkg("python3"),  # agents-private のスキルと scripts/check.sh が直接呼ぶ。
            pkg("gh"),
            pkg("ghostscript"),
            pkg("poppler-utils"),
            pkg("mpv"),
            pkg("fd"),
            pkg("ripgrep"),
            pkg("jq"),
            pkg("xh"),
            pkg("tdf"),
        ],
        "programs.home-manager.enable": True,
        "programs.bash.enable": True,
        "programs.bash.enableCompletion": True,
        "programs.bash.historyControl": ["ignoredups", "ignorespace"],
        "programs.bash.shellAliases": {
            "ls": "eza --icons --git",
            "ll": "eza -l --icons --git",
            "la": "eza -la --icons --git",
            "cat": "bat",
            "grep": "rg",
            "top": "btm",
            "cd": "z",
            # yazi=y は、y の中の yazi の呼び出しと無限に再帰するので置かない。
        },
        "programs.bash.initExtra": _NOISE,
        "programs.starship.enable": True,
        "programs.starship.settings": {
            "add_newline": True,
            "character": {
                "success_symbol": "[❯](bold green)",
                "error_symbol": "[✗](bold red)",
            },
            "package": {"disabled": True},
            "aws": {"disabled": True},
            "gcloud": {"disabled": True},
        },
        "programs.fzf.enable": True,
        "programs.fzf.enableBashIntegration": True,
        "programs.zoxide.enable": True,
        "programs.zoxide.enableBashIntegration": True,
        "programs.eza.enable": True,
        "programs.bat.enable": True,
        "programs.bottom.enable": True,
    }}

_NOISE = """noise() {
  local dir="${1:-$HOME/音楽/noise}"
  local volume="${2:-50}"
  mpv --shuffle --loop-playlist --no-video --really-quiet "--volume=$volume" "$dir"
}
"""
