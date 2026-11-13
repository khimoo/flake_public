# 手段: Codex の方針（サブエージェントと sol-handoff を止める）を、エージェントのシステム層（/etc/codex/config.toml）に書く。/etc は NixOS の設定でしか書けない。
needs = ["nixos_system"]
_codex = """# このファイルは flake の config/elements/codex_policy.star が生成する。直接編集しないこと。

# サブエージェント (spawn_agent 等のマルチエージェントツール) を無効化する。
[agents]
enabled = false

# `features.multi_agent_v2` が有効になっていると、`agents.enabled = false` よりも優先されます。
# そのため、完全に無効化するには両方の設定をあわせて記述する必要があります。
[features]
multi_agent_v2 = false

# sol-handoff は Codex の astra のプロファイル（agents-private の codex/astra.config.toml）でだけ有効に戻す。
# sol のセッションが sol 自身に渡すのを防ぐため。Alook の Codex のボットは --profile なしで動くので、ここで止める。
[[skills.config]]
name = "sol-handoff"
enabled = false
"""

def config(incoming):
    # マシン固有の指示（agent_offload_notes が書き込む）は、TOML のテーブル見出しより前に置かないと、そのテーブルのキーになる。
    notes = [w.value for w in incoming]
    text = concat("developer_instructions = ", toJSON(concat(*notes)), "\n", _codex) if notes else _codex
    return {"nixos": {("environment", "etc", "codex/config.toml", "text"): text}}
