# 目的: 自分用サーバとして、ほかのホストの Nix のビルドを引き受ける。
# ビルドを任せるユーザー（ssh で接続してくるユーザー）を信頼する。信頼しないと、nix-daemon は derivation のビルドと、署名のないパスの受け取りを拒否する。
# 同時に実行する数は、このホストの nix.settings.max-jobs（既定は "auto"）で決まり、machine_base の idle で作業中は譲る。
# KVM が要るビルド（kvm、nixos-test）も引き受けるホストは、あわせて serve_kvm_builds を選ぶ。
role = True

def user_config(user):
    return {"nixos": {"nix.settings.trusted-users": [user.name]}}
