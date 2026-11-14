# `cargo remote-run`: 自分用サーバの作業場所（serve_workspace）で build し、手元で実行する。
# cargo は devShell のものを、nix はシステムのものを使うので入れない。
requires = ["find_home_server"]
def user_config(find_home_server):
    return {"home": {"home.packages": [shellAppEnv(
        "cargo-remote-run",
        [pkg("openssh"), pkg("rsync"), pkg("coreutils"), pkg("gnugrep")],
        {"CARGO_REMOTE_RUN_HOST": find_home_server.services["serve_workspace"]["tailnet"]},
        repoText("modules/home-manager/dev/cargo-remote-run.sh"),
    )]}}
