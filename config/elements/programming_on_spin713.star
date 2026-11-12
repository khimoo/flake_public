# spin713 でプログラムを書くときは、デスクトップのファイルを sshfs で開き、build と Alook をデスクトップで動かす。
when = ["programming", "machine_nixos_spin713"]
requires = ["sshfs_editing", "cargo_remote_run", "alook_open"]
