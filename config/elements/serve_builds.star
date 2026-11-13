# 目的: 自分用サーバとして、ほかの機体の Nix のビルドを引き受ける。
# ビルドを任せる利用者（ssh で接続してくる利用者）を信頼する。信頼しないと、nix-daemon は derivation のビルドと、署名のないパスの受け取りを拒否する。
# 同時に実行する数は、この機体の nix.settings.max-jobs（既定は "auto"）で決まり、machine_base の idle で作業中は譲る。
def user_config(user):
    return {"nixos": {"nix.settings.trusted-users": [user.name]}}
