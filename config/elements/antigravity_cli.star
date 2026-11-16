# gemini-proofread のスキルが Gemini の API で校正できないときの予備の経路（Antigravity CLI、agy）。
requires = ["llm_agents"]
needs = ["x86_64_linux"]

def user_config():
    return {"home": {"home.packages": [pkg("antigravity-cli")]}}
