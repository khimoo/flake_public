# Codex CLI のシステム層設定 (/etc/codex/config.toml) を宣言する。
#
# サブエージェントを無効化する理由、退けた案、戻す条件、効いているかの確認方法は
# docs/architecture/codex-subagents.md と docs/howtouse/codex-subagents.md にある。
# ~/.codex/config.toml は Codex 自身が信頼済みディレクトリや選択中モデルを書き込む live な
# ファイルなので、宣言した設定はシステム層に置く。
#
# 依存方向: OS → ユーザー環境への一方向。~/.codex/config.toml に同じキーを書くと
# このファイルは効かなくなる。
{ ... }:
{
  environment.etc."codex/config.toml".text = ''
    # このファイルは flake の modules/nixos/codex.nix が生成する。直接編集しないこと。

    # サブエージェント (spawn_agent 等のマルチエージェントツール) を無効化する。
    [agents]
    enabled = false

    # features.multi_agent_v2 が有効だと agents.enabled = false より優先されるため、
    # 両方を書かないと無効化しきれない。
    [features]
    multi_agent_v2 = false
  '';
}
