# gemini-proofread のスキルが Gemini の API で校正できないときの予備の経路（Antigravity CLI、agy）。
# 版を固定しているのは x86_64-linux の配布物だけ。
needs = ["x86_64_linux"]

def user_config():
    return {"home": {"home.packages": [repoPkg("packages/antigravity-cli")]}}
