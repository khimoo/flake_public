# プログラムのファイルとビルドをデスクトップに置く機体では、ファイルを sshfs で開き、build と Alook をデスクトップで動かす。
when = ["programming", "remote_workspace"]
requires = ["sshfs_editing", "cargo_remote_run", "alook_open"]
