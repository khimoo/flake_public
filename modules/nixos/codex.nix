# Codex CLI のシステム層設定 (/etc/codex/config.toml) を宣言する。
#
# 動機:
#   Codex のサブエージェント (MultiAgentV2) は既定で「親の会話履歴を全部コピーして
#   子エージェントに渡す」挙動になっており、有効化して実際に呼び出すと入力コンテキストが増える。
#   この判断の根拠と戻し方を残せる場所が要る。~/.codex/config.toml は Codex 自身が
#   信頼済みディレクトリ・選択中モデル・TUI のカウンタを書き込む live なファイルなので、
#   宣言した設定の置き場としては適さない。
#
# 設計:
#   Codex の設定はレイヤ構造で、下から
#     /etc/codex/config.toml (system) → ~/.codex/config.toml (user)
#       → <repo>/.codex/config.toml (project・信頼済みのみ) → -c フラグ (runtime)
#   の順に上書きされる。system 層は Codex が書き込まないため、nix store の
#   読み取り専用ファイルを置ける。可変な状態は ~/.codex/config.toml に残る。
#
# 依存方向: OS → ユーザー環境への一方向。ユーザー側の上書きは常に勝つ。
#   逆に言うと、~/.codex/config.toml に同じキーを書くとこのファイルは効かなくなる。
{ ... }:
{
  environment.etc."codex/config.toml".text = ''
    # このファイルは flake の modules/nixos/codex.nix が生成する。直接編集しないこと。

    # サブエージェント (spawn_agent 等のマルチエージェントツール) を無効化する。
    #
    # 理由:
    #   MultiAgentV2 の spawn_agent は fork_turns 引数を省略すると "all"、すなわち
    #   親の会話履歴を丸ごと子へコピーする。子を N 個生やすと入力トークンが
    #   親のコンテキスト長 × N になる。さらに全履歴 fork では agent_type / model /
    #   reasoning_effort の指定が拒否されるため、安いモデルへの委譲もできない。
    #   導入時点のセッションログを全走査したところ spawn_agent の呼び出しは 0 件で、
    #   現状使っていない機能なので、将来の意図しない全履歴forkを避けるため無効化した。
    #   呼び出し0件はforkの実消費を示す証拠ではない (2026-09-07 時点)。
    #   コードレビューは `codex review` (TUI では /review) が履歴を持たない別スレッドで
    #   走る独立した機能なので、無効化しても失われない。
    #
    # 戻したくなる条件:
    #   - OpenAI 側が既定を fork_turns="none" 相当に変えた
    #   - 並列調査をサブエージェントに任せたくなった
    #   その場合は enabled を true に戻す。全部戻さずトークンだけ抑えたいなら
    #   [features.multi_agent_v2] を有効にしたうえで root_agent_usage_hint_text に
    #   「spawn_agent は fork_turns="none" で呼ぶこと」と書く手もある。
    #
    # 効いているかの確認 (どちらも API を叩かない):
    #   codex features list | grep multi_agent_v2    → false
    #   codex debug prompt-input | grep spawn_agent  → 出力なし
    [agents]
    enabled = false

    # モデル側のピン留めで v2 が有効化される経路を塞ぐ。
    # features.multi_agent_v2 が有効だと agents.enabled = false より優先されるため、
    # 両方を書かないと無効化しきれない (codex-rs/core/src/config/mod.rs の
    # multi_agent_version_override)。
    [features]
    multi_agent_v2 = false
  '';
}
