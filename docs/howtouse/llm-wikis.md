# LLM Wiki（AI に読ませる知識ベース）の使い方

`khimoo/llm-wikis`（private）を `/home/pomu/sagyo/llm-wikis` に置き、ドメインごとの
知識ベースを Claude 自身に育てさせる運用。二次情報が矛盾していたり、Claude が既定で
誤答する領域について、調査結果を蓄積して次回以降の参照先にする。

設計判断は [docs/architecture/llm-wikis.md](../architecture/llm-wikis.md) を参照。

## 配置

clone は switch 時に [private-repos.nix](../../modules/home-manager/private-repos.nix) が行う
（`flake.nix` の `llmWikisRoot` / `llmWikisRepoUrl`）。dest が既にあれば触らないので、
手動 clone 済みの環境でも安全。仕組みは [private-repo-clone.md](./private-repo-clone.md) と共通。

```
llm-wikis/
  CLAUDE.md                 ルータ。ドメインディレクトリで作業させる指示だけ
  minecraft-java/
    CLAUDE.md               このドメインの wiki スキーマ
    raw/<topic>/            収集した一次資料（不変。LLM は読むだけ）
    wiki/<topic>/*.md       記事（LLM が所有）
    wiki/index.md           全記事の目録
    wiki/log.md             追記のみの操作記録
```

`raw/` と `wiki/` のトピック別サブディレクトリは 1 階層まで。

`~/.claude` への配線は無い。スキーマはカレントディレクトリの `CLAUDE.md` として効く。

## 使う

対象ドメインのディレクトリで Claude Code を起動する。

```sh
cd ~/sagyo/llm-wikis/minecraft-java && claude
```

そのうえで 3 つの操作を回す。

| 操作 | 何を頼むか | 何が起きるか |
|---|---|---|
| ingest | 資料の URL を渡して「取り込んで」と頼む | 資料が `raw/` に保存され、記事が作成・更新される。`index.md` と `log.md` も更新される |
| query | 普通に質問する | `wiki/` を読んで答える。確信のあるページが無ければ「無い」と答える |
| lint | 「lint して」と頼む | index のずれとリンク切れは自動で直し、記事間の矛盾・confidence やバージョンの記載漏れは報告だけする |

query の答えが wiki に無かった場合、その場で調べた結果は**そのままでは wiki に入れない**。
一次資料を `raw/` に置いてから ingest する。推論で埋めたページが次回の出典になるのが
このパターン最大の失敗なので、経路を分けてある。

## 新しいドメインを足す

1. `llm-wikis/` 直下にドメイン名のディレクトリを作る
2. 既存ドメインの `CLAUDE.md` を写し、対象領域・confidence の判定基準・バージョン表記を
   書き換える。`raw/` と `wiki/index.md` / `wiki/log.md` も置く
3. root の `CLAUDE.md` のドメイン表に 1 行足す

flake 側は何も要らない。repo 全体が 1 つの clone 対象なので、ドメインが増えても配線は変わらない。

## スキーマに必ず入れるもの

`<domain>/CLAUDE.md` を書くとき、以下が抜けていると事故が起きる。

- **confidence をページ内にインラインで書かせる。** 別ファイルにすると本文だけ読んだ
  ときに断定される
- **確信のある答えが無いときは「無い」と言わせる。** 関連度の低い情報からの推論を禁じる
- **全記事に対象バージョン（`Version:`）と更新日（`Updated:`）を書かせる**
- **AI が踏みやすい誤りを明示的に書かせる。** Wiki を読めば分かることの転記より、
  既定の挙動を訂正する情報のほうが役に立つ
- **wiki に書く数値・引用は `raw/` の中に同じ形で存在することを確かめさせる。**
  `raw/` を不変にしているのはこの対応関係を保つため

## 無効化する

`flake.nix` の `llmWikisRepoUrl` を消す（既定 `null`）と自動 clone が止まる。
`llmWikisRoot` を残しても現状は何も起きない（読むモジュールが無い）ので、両方消してよい。
