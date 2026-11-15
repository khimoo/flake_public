# 利用目的（趣味）: 音楽を作る・耳コピする。
requires = ["music_production", "temp_storage", "use_ai_agents", "mimikopi"]

def writes(gui_apps):
    return [write(gui_apps, app) for app in [
        {"pkg": pkg("transcribe")},
        {"pkg": pkg("vmpk")},
    ]]
