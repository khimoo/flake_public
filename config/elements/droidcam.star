# 手段: スマホを Web カメラにする（DroidCam）。USB 接続には adb を使う。
needs = ["nixos_system"]

def config():
    return {"nixos": {
        "programs.droidcam.enable": True,
        "environment.systemPackages": [pkg("android-tools")],
    }}
