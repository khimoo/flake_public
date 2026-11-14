# 目的: 自分用サーバとして、プログラムの作業場所（ssh でつながるファイル、cargo のビルド）を公開する（サーバの側）。
# ほかの機体は、行動 program_on_home_server で接続する。
requires = ["ssh_server"]
role = True
