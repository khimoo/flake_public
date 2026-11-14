# 自分用サーバを動かすアカウントは、クライアントの機体からの ssh のログインを受け付ける。
when = ["ssh_server", "run_home_server"]
requires = ["authorize_lan_key"]
role = True
