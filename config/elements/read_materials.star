# 利用目的（勉強）: 資料を読んで覚える（PDF、電子書籍、手書きのノート、Quaderno との受け渡し、Anki、SNS を塞いで集中する）。
requires = ["quaderno_exchange", "use_quaderno_archive", "sns_block", "task_management", "use_ai_agents"]

def writes(gui_apps):
    # Obsidian は memex が git / claude を含むラッパーを入れるため、素のパッケージを重ねない。
    return [
        write(gui_apps, pkg = pkg("xournalpp")),
        write(gui_apps, pkg = pkg("pdfarranger")),
        # 文書は zathura で開く。zathura はプラグインごとに .desktop を持つため、形式ごとにエントリを分ける。
        # プラグインが宣言する EPUB は Foliate に、ZIP・TAR・フォルダは他のアプリに任せるため既定にしない。
        write(gui_apps, pkg = pkg("zathura"), desktop = "org.pwmt.zathura-pdf-mupdf.desktop", mime = [
            "application/pdf",
            "application/oxps",
            "image/svg+xml",
            "image/jpeg",
            "image/png",
            "image/bmp",
            "image/x-bmp",
            "image/tiff",
            "image/tiff-fx",
        ]),
        write(gui_apps, pkg = pkg("zathura"), desktop = "org.pwmt.zathura-djvu.desktop", mime = ["image/vnd.djvu", "image/vnd.djvu+multipage"]),
        write(gui_apps, pkg = pkg("zathura"), desktop = "org.pwmt.zathura-ps.desktop", mime = [
            "application/postscript",
            "application/eps",
            "application/x-eps",
            "image/eps",
            "image/x-eps",
        ]),
        write(gui_apps, pkg = pkg("zathura"), desktop = "org.pwmt.zathura-cb.desktop", mime = [
            "application/x-cbr",
            "application/x-cbz",
            "application/x-cb7",
            "application/x-cbt",
        ]),
    ]

def user_config():
    return {"home": {
        "programs.foliate.enable": True,
        "programs.anki.enable": True,
        "programs.anki.language": "ja_JP",
    }}
