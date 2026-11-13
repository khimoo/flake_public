# 手段: Rust でプログラムを書く。toolchain はプロジェクトの devShell が持つので、ここでは cargo のビルドの並列数だけを決める。
# 環境変数（CARGO_BUILD_JOBS）ではなく設定ファイルに書く。Home Manager の環境変数は ~/.profile でしか読まれず、ssh 越しの cargo remote-run には渡らない。
def user_config():
    return {"home": {("home", "file", ".cargo/config.toml", "text"): "[build]\njobs = 8\n"}}
