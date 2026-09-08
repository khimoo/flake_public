# Codex のサブエージェント設定

Codex CLI のサブエージェント（`spawn_agent` 等のマルチエージェントツール）を
無効化してある。理由と退けた案は
[docs/architecture/codex-subagents.md](../architecture/codex-subagents.md) を参照。

## NixOS の場合

[modules/nixos/codex.nix](../../modules/nixos/codex.nix) が
`/etc/codex/config.toml` を生成する。`modules/nixos/common.nix` から import 済みなので
rebuild するだけで効く。設定を変えたいときはこのファイルを編集する。

## NixOS 以外（WSL / macOS）の場合

home-manager 単独構成では `/etc` を管理できないので、`~/.codex/config.toml` に
同じ内容を手で書く。設定は次の 6 行だけ。

```toml
[agents]
enabled = false

[features]
multi_agent_v2 = false
```

両方書くこと。`features.multi_agent_v2` が有効だと `agents.enabled` より優先されるため、
`[agents]` だけではモデル側のピン留めで v2 が復活する。

コメントを添えたい場合は TOML に直接書いてよい。Codex は `toml_edit` で差分だけを
適用するので、Codex 自身が設定を書き換えてもコメントは残る。ただし値の表現は
正規化されることがある（`multi_agent_v2 = false` が
`[features.multi_agent_v2]` + `enabled = false` に展開される等）。

## 効いているかの確認

どちらも API を叩かないので気軽に実行してよい。

```sh
codex features list | grep multi_agent_v2    # false なら無効
codex debug prompt-input | grep spawn_agent  # 何も出なければ無効
```

`codex debug prompt-input` はモデルに渡すプロンプトを JSON で出力する。
サブエージェントが有効だと `spawn_agent` の使い方を説明する developer メッセージが
含まれるので、その有無で判定できる。

`grep -c` で件数を数える形にしないこと。`grep` が ripgrep に割り当てられている環境では
一致 0 件のとき何も出力せず終了コード 1 になり、GNU grep の `0` という表示と挙動が違う。
件数が要るなら次のようにする。

```sh
codex debug prompt-input | python3 -c 'import sys; print(sys.stdin.read().count("spawn_agent"))'
```

## 有効に戻す

NixOS なら `modules/nixos/codex.nix` の `enabled` を `true` にして rebuild する。
それ以外なら `~/.codex/config.toml` の該当行を消す。

戻したうえでトークン消費だけ抑えたいなら、`spawn_agent` を呼ぶときに
`fork_turns` を指定させる。値の意味は次のとおり。

| 値 | 挙動 |
|----|------|
| `"all"`（省略時の既定） | 親の会話履歴を全部コピーする |
| `"3"` のような正整数の文字列 | 直近 N ターンだけ渡す |
| `"none"` | 履歴を渡さない。role 指示とタスク文だけ |

`fork_turns` は設定ファイルのキーではなく `spawn_agent` の引数なので、既定値を
config で決めることはできない。`AGENTS.md` に書くか、
`features.multi_agent_v2.root_agent_usage_hint_text`（`spawn_agent` のツール説明文に
差し込まれる）で指示する。

## レビューは無効化の影響を受けない

`codex review`（TUI では `/review`）はサブエージェントとは別の機構で、
履歴を持たない専用スレッドで走る。無効化した状態でもそのまま使える。
