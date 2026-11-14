# 自分用サーバで作業する機体で AI エージェントを使うとき、重い処理は自分用サーバで実行するよう、エージェントのシステム層に指示を書く。
# 接続先は、自分用サーバの作業場所（serve_workspace）。Claude Code は /etc/claude-code/CLAUDE.md、Codex は codex_policy の developer_instructions で読む。
when = ["program_on_home_server", "codex_policy"]

def _notes(find_home_server):
    server = find_home_server.services["serve_workspace"]["tailnet"]
    return """# このマシン

このマシンは、重い処理を自分用サーバ（`ssh %s`）に任せる。

- メモリを多く使う処理と GPU が要る処理は、まず自分用サーバで実行できるか確かめ、できればそこで実行する。作業ツリーは自分用サーバの `/tmp` にコピーして使う。
- 自分用サーバで実行できないときは、処理のピークメモリと CPU 負荷を概算し、`nproc` と `free -m` で確かめたこのマシンの空きと比べて、フリーズしないと判断できたときだけ手元で実行する。判断できなければ実行せず、人間に確認する。
- Nix のビルドは自分用サーバに任せる。手元でビルドするときは、上の判断を経てから `--max-jobs` を渡す。
""" % server

def writes(codex_policy, find_home_server):
    return [write(codex_policy, _notes(find_home_server))]

def config(find_home_server):
    return {"nixos": {("environment", "etc", "claude-code/CLAUDE.md", "text"): _notes(find_home_server)}}
