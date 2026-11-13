# 行動（勉強）: 資料を読んで覚える（PDF、電子書籍、手書きのノート、Quaderno との受け渡し、Anki、SNS を塞いで集中する）。
requires = ["quaderno_send", "use_quaderno_archive", "sns_block", "task_management", "use_ai_agents"]

def writes(gui_apps):
    # Obsidian は memex が git / claude を含むラッパーを入れるため、素のパッケージを重ねない。
    return [write(gui_apps, app) for app in [
        {"pkg": pkg("xournalpp")},
        {"pkg": pkg("pdfarranger"), "desktop": "pdfarranger.desktop", "mime": ["application/pdf"]},
    ]]

def user_config():
    return {"home": {
        "programs.foliate.enable": True,
        "programs.anki.enable": True,
        "programs.anki.language": "ja_JP",
    }}
