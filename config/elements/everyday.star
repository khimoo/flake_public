# 行動: 日常の作業（端末、ファイルの編集、文書、パスワードの管理）。
requires = ["shell", "git", "daily_editing"]

def writes(gui_apps):
    return [write(gui_apps, app) for app in [
        {"pkg": pkg("bitwarden-desktop")},
        {"pkg": pkg("libreoffice")},
        {"pkg": pkg("pdfarranger"), "desktop": "pdfarranger.desktop", "mime": ["application/pdf"]},
        # Takeout の日本語ファイル名を保った解凍には p7zip が必要。
        {"pkg": pkg("p7zip")},
        {"pkg": pkg("sticky-notes"), "name": "sticky-notes", "bin": "com.vixalien.sticky", "desktop": "com.vixalien.sticky.desktop", "autostart": True},
        {"pkg": pkg("tdf")},
        {"pkg": pkg("showmethekey")},
    ]]
