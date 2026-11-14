# ホストを管理するアカウント（etc_nixos_link）は、ほかの機体からの ssh のログインを受け付ける（nixos-rebuild の --target-host など）。
# connect_ssh は、このアカウントを Host ブロックのログイン名にする。
when = ["ssh_server", "etc_nixos_link"]
requires = ["authorize_lan_key"]
role = True
