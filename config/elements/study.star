# 行動: 勉強する（ノート、資料の閲覧、Quaderno への送信、SNS を塞いで集中する）。
requires = ["shell", "git", "daily_editing", "memex_sync", "obsidian", "quaderno_send", "sns_block"]

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
