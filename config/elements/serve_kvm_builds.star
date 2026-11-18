# 目的: 自分用サーバとして、KVM が要る Nix のビルド（kvm、nixos-test）も引き受ける。
needs = ["local_kvm"]
requires = ["serve_builds"]
role = True
