# 目的: 自分用サーバとして、ほかのホストの Nix のビルドを引き受ける。
# ビルドを任せるユーザー（ssh で接続してくるユーザー）を信頼する。信頼しないと、nix-daemon は derivation のビルドと、署名のないパスの受け取りを拒否する。
# 同時に実行する数は、このホストの nix.settings.max-jobs（既定は "auto"）で決まり、machine_base の idle で作業中は譲る。
# 任せる側（remote_build）は kvm を要求するビルドも送るので、KVM のないホストでは引き受けない。
needs = ["local_kvm"]
role = True

def user_config(user):
    return {"nixos": {"nix.settings.trusted-users": [user.name]}}
