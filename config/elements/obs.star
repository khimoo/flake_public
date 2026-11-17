# 手段: OBS Studio（キー入力を映像に重ねる input-overlay プラグイン付き）。
requires = ["gui"]

def user_config():
    return {"home": {
        "programs.obs-studio.enable": True,
        "programs.obs-studio.plugins": [pkg("obs-studio-plugins.input-overlay")],
    }}
