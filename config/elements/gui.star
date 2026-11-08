# 目的: デスクトップの GUI。端末（kitty）、フォント、GUI アプリの土台。
requires = ["kitty", "inkscape", "gui_apps", "firefox", "teams_dispatcher"]

def public():
    return {"terminal_font": {"package": pkg("plemoljp-nf"), "name": "PlemolJP Console NF"}}

def config():
    return {"home": {
        "home.packages": [
            pkg("plemoljp-nf"),
            pkg("ipafont"),
            pkg("ipaexfont"),
            pkg("noto-fonts"),
            pkg("noto-fonts-cjk-sans"),
            pkg("noto-fonts-color-emoji"),
        ],
        "fonts.fontconfig.enable": True,
        # kitty の背景透過と、nvim の背景透過の autocmd を連携させる（modules/home-manager/dev/neovim/config/）。
        "home.sessionVariables.TERMINAL_TRANSPARENT": "1",
        "programs.obs-studio.enable": True,
        "programs.obs-studio.plugins": [pkg("obs-studio-plugins.input-overlay")],
        "programs.foliate.enable": True,
        "programs.anki.enable": True,
        "programs.anki.language": "ja_JP",
    }}
