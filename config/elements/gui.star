requires = ["kitty"]

_DEFAULT_FONTS = {
    "sansSerif": ["IBM Plex Sans JP", "Noto Sans CJK JP"],
    "serif": ["IBM Plex Serif", "Noto Serif CJK JP"],
    "monospace": ["PlemolJP Console NF", "IBM Plex Mono", "Noto Sans Mono CJK JP"],
    "emoji": ["Noto Color Emoji"],
}

def _font_packages():
    return [
        pkg("ibm-plex"),
        pkg("plemoljp-nf"),
        pkg("ipafont"),
        pkg("ipaexfont"),
        pkg("noto-fonts"),
        pkg("noto-fonts-cjk-sans"),
        pkg("noto-fonts-cjk-serif"),
        pkg("noto-fonts-color-emoji"),
    ]

def public():
    return {
        "terminal_font": {"package": pkg("plemoljp-nf"), "name": "PlemolJP Console NF"},
        "font_packages": _font_packages(),
        "default_fonts": _DEFAULT_FONTS,
    }

def user_config():
    return {"home": {
        "home.packages": _font_packages(),
        "fonts.fontconfig.enable": True,
        "fonts.fontconfig.defaultFonts": _DEFAULT_FONTS,
        # kitty の背景透過と、nvim の背景透過の autocmd を連携させる（modules/home-manager/dev/neovim/config/）。
        "home.sessionVariables.TERMINAL_TRANSPARENT": "1",
    }}
