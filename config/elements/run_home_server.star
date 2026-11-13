# 行動: 自分用サーバを動かす。ほかの機体とこの機体のクライアント（use_quaderno_archive、use_xsaved、use_alook、program_on_home_server）が ssh で接続して使う。
requires = ["serve_quaderno_archive", "serve_xsaved", "serve_workspace", "serve_alook", "serve_remote_desktop", "stay_awake"]

def user_config(user):
    # サーバのサービス（xsaved の定期実行など）は systemd のユーザーのユニットなので、ログインしていなくても動かす。
    return {"nixos": {("users", "users", user.name, "linger"): True}}
