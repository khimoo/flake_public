# 耳コピの ML モデルは GPU を使うので、ROCm の計算ができる機体で音楽を作るときだけ入れる。
when = ["make_music", "rocm_compute"]
requires = ["mimikopi"]
