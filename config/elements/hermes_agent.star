# 手段: Hermes Agent（作業の経験からスキルを書き足す AI エージェント）を使う。
requires = ["llm_agents"]

def user_config():
    return {"home": {"home.packages": [pkg("hermes-agent")]}}
