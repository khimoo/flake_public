# 手段: Blender で 3D のモデルを作る。ROCm 版なので、ROCm で GPU の計算ができるホストでだけ使える。
needs = ["rocm_compute"]

def user_config():
    return {"home": {"home.packages": [pkg("pkgsRocm.blender")]}}


def config():
    return {"nixos": {
        "hardware.graphics.enable": True,
        "systemd.tmpfiles.rules": [concat("L+    /opt/rocm   -    -    -     -    ", symlinkJoin("rocm-combined", [pkg("rocmPackages.rocblas"), pkg("rocmPackages.hipblas"), pkg("rocmPackages.clr")]))],
    }}
