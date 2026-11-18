# 目的: 自分用サーバとして、プログラムの作業場所（ssh でつながるファイル、cargo のビルド）を公開する（サーバの側）。
# ほかのホストは、利用目的 program_on_home_server で接続する。
# cargo-remote-run は devShell を署名なしで nix copy し、ソースを rsync で送るので、trusted-users と rsync が要る。
requires = ["ssh_server"]
role = True

def user_config(user):
    return {
        "home": {"home.packages": [pkg("rsync")]},
        "nixos": {"nix.settings.trusted-users": [user.name]},
    }
