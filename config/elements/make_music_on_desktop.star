# 耳コピの ML モデルは GPU を使うので、デスクトップで音楽を作るときだけ入れる。
when = ["make_music", "machine_nixos_desktop"]
requires = ["mimikopi"]
