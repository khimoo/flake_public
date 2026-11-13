# 手段: Google Apps Script のプロジェクトを手元で編集してアップロードする（clasp）。メールの整理のスクリプトに使う。
def user_config():
    return {"home": {"home.packages": [pkg("google-clasp")]}}
