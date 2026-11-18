# 手段: このアカウントが動かす serve_* のサービスを、ほかのホストのクライアント（find_home_server）へ ssh と tailnet で公開する。
# 自宅の PC でもクラウドの VM でも使え、個人の秘密一式（personal_files）を要求しない。
requires = ["ssh_server", "authorize_lan_key", "tailscale"]
role = True

def user_config(user):
    # サーバのサービス（xsaved の定期実行など）は systemd のユーザーのユニットなので、ログインしていなくても動かす。
    return {"nixos": {("users", "users", user.name, "linger"): True}}
