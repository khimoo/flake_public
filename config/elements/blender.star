# 手段: Blender で 3D のモデルを作る。ROCm 版なので、ROCm で GPU の計算ができる機体でだけ使える。
needs = ["rocm_compute"]

def user_config():
    return {"home": {"home.packages": [pkg("pkgsRocm.blender")]}}
