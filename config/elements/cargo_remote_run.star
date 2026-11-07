# `cargo remote-run`: 別のホストで build し、手元で実行する。build するホストはホストのファイルの
# cargo_remote_run_host。cargo は devShell のものを、nix はシステムのものを使うので入れない。
def config(host):
    return {"home": {"home.packages": [shellAppEnv(
        "cargo-remote-run",
        [pkg("openssh"), pkg("rsync"), pkg("coreutils"), pkg("gnugrep")],
        {"CARGO_REMOTE_RUN_HOST": host.cargo_remote_run_host},
        repoText("modules/home-manager/dev/cargo-remote-run.sh"),
    )]}}
