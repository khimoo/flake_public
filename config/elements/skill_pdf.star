# 手段: agents-private の docx と pdf のスキル（claude.ai から同期した Anthropic のスキル）が、PDF をテキストと画像にするための poppler-utils（pdftotext、pdftoppm）。
# スキルを外したら、この要素も claude_code の requires から外す。
def user_config():
    return {"home": {"home.packages": [pkg("poppler-utils")]}}
