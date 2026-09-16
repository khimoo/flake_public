# Codex CLI のシステム層の設定（/etc/codex/config.toml）を宣言します。
#
# サブエージェントを無効化する理由、不採用とした代替案、有効に戻す条件、および設定が適用されて
# いるかどうかの確認方法は、docs/architecture/codex-subagents.md と
# docs/howtouse/codex-subagents.md に記載されています。
# ~/.codex/config.toml は、Codex 自身が信頼済みディレクトリや選択中のモデルを動的に書き込む
# ファイルであるため、宣言的に管理したい設定はシステム層（/etc）に配置します。
#
# 依存関係の方向：OS からユーザー環境への一方向です。~/.codex/config.toml に同じ設定キーを
# 記述すると、この（システム側の）設定ファイルは適用されなくなるため注意してください。
{ ... }:
{
  environment.etc."codex/config.toml".text = ''
    # このファイルは flake の modules/nixos/codex.nix が生成する。直接編集しないこと。

    # サブエージェント (spawn_agent 等のマルチエージェントツール) を無効化する。
    [agents]
    enabled = false

    # `features.multi_agent_v2` が有効になっていると、`agents.enabled = false` よりも優先されます。
    # そのため、完全に無効化するには両方の設定をあわせて記述する必要があります。
    [features]
    multi_agent_v2 = false
  '';
}
