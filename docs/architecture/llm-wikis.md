# LLM Wiki 群を独立 private repo に置く（設計判断）

使い方は [docs/howtouse/llm-wikis.md](../howtouse/llm-wikis.md) を参照。
flake 側の実装は `flake.nix` の `llmWikisRoot` / `llmWikisRepoUrl` と、それを受ける
[modules/home-manager/private-repos.nix](../../modules/home-manager/private-repos.nix) のみ。

## 何を解決するか

Minecraft Java Edition の内部仕様を調べたところ、二次情報（各種 Wiki・解説記事）が
相互に矛盾しており、単独では信頼できなかった。Claude はこの領域で確信度の高い誤答を返す。
同じ調査を毎回やり直すのを避けるため、**LLM が読むことを目的とした知識ベース**を置く。
人間向けのノートではなく、AI に参照させる資料である。

採用したのは Karpathy の LLM Wiki パターン[^1]。raw（収集した一次資料・不変）/
wiki（LLM が生成・維持する markdown）/ CLAUDE.md（スキーマ）の三層と、
ingest / query / lint の三操作からなる。

第一のドメインは Minecraft Java Edition、第二のドメインは Rust を予定している。

## 独立した private repo にする

`khimoo/llm-wikis` を新設し、`/home/pomu/sagyo/llm-wikis` へ clone する。
既存の repo に相乗りさせる案は 2 つとも退けた。

### Claude 設定 repo（`khimoo/claude-private`）に混ぜない

- **履歴が濁る。** wiki は LLM が書く層で、1 回の ingest で 10〜15 ファイルが同時に
  書き換わる。CLAUDE.md や skills は意図的な低頻度の編集で、同居すると設定の履歴が
  自動生成コミットに埋もれる。[zettelkasten-vault-skeleton.md](./zettelkasten-vault-skeleton.md)
  で同居方式を退けたのと同じ理由
- **レイアウト規約が壊れる。** [dev/claude.nix](../../modules/home-manager/dev/claude.nix) は
  `<root>/CLAUDE.md` と `<root>/skills/` という `~/.claude` の鏡写しを前提にしている。
  `wikis/` を足すと `configDirs` に無いディレクトリが repo に生まれ、規約が実態とずれる
- **`CLAUDE.md` の役割が二重になる。** claude-private の root の CLAUDE.md はグローバル指示、
  LLM Wiki の CLAUDE.md はドメインのスキーマで、同名だが別物
- **公開の自由度を失う。** wiki の内容に機密性は無い。特に Rust wiki は将来 public に
  したくなるかもしれず、private repo に入れると履歴の切り出しが要る

### Zettelkasten vault に入れない

- **書き手が違う。** Zettel は自分が書くもの、LLM Wiki は LLM が書くもの。混ぜると
  自分の思考と機械の出力を区別できなくなる
- **リンクグラフが薄まる。** Zettelkasten の価値は自分の思考どうしの接続にある。
  外部仕様のページが大量に流入すると Obsidian のグラフビューが機能しなくなる
- **`obsidian-git` の auto-commit と衝突する。** ingest 中の一括書き換えの途中で
  auto-commit が走ると、中途半端な状態が同期に流れる
- **骨格の allowlist の分類が壊れる。** `nix/skeleton-paths.nix` は「骨格（配る）」と
  「個人ノート（配らない）」の二分だが、LLM Wiki はどちらでもない
- **得るものが無い。** 「Obsidian で見たい」は別 repo でも達成できる。Obsidian は
  任意のフォルダを vault として開ける

## ドメインごとに repo を分けず、モノレポにする

`minecraft-java/` と `rust/` を 1 つの repo に置く。各ドメインがスキーマ（`CLAUDE.md`）と
目録・記録（`wiki/index.md` / `wiki/log.md`）を独立して持ち、index も lint もドメイン内に
閉じる。「同じ repo に住んでいる別々の wiki」という形。

「1 wiki = 1 ドメイン」を慣習として扱っているが、これは既存実装の挙動からの推測で、
明文化された規約は見つけていない。index の希釈や lint の破綻も gist の記述からの
演繹であり、実測ではない。ドメインが増えて index が使いものにならなくなったら分割する。

## Claude Code の skill にしない

LLM Wiki パターンはカレントディレクトリの `CLAUDE.md` をスキーマとして使うので、
skill 機構を必要としない。運用は該当ドメインのディレクトリで Claude Code を起動するだけで、
`~/.claude/skills` への配線は要らない。skill 形式の実装[^2]も存在するが、必須ではなく、
配線を増やすことになる。

## flake がやるのは clone だけ

結果として flake 側の変更は `buildPrivateRepos` のリストに 1 行足すことに尽きる。
新しい home-manager モジュールは作らず、`~/.claude` 配下への symlink も張らない。
[private-repo-clone.md](./private-repo-clone.md) の「新しい private repo を足すときは
`flake.nix` に 1 行」がそのまま効いた形。

`llmWikisRoot` は `settings` に `inherit` していない。`claudeConfigRoot` や
`vaultSkeletonRepo` は読み手のモジュールがあるので settings 経由で渡しているが、
LLM Wiki には読み手が無く、渡すと「何がこれを使っているのか」を追う手間だけが増える。
将来モジュールが要るようになった時点で足せばよい。

## スキーマ側に持たせる要件

flake の配線とは別に、`<domain>/CLAUDE.md` に以下を含める。いずれも今回の調査で
実際に起きた失敗に基づく。

1. **confidence をページ内にインラインで持つ。** 別ファイルに切り出すと、本文だけ読んだ
   エージェントが断定する
2. **「wiki に確信のある答えが無い」と言わせる。** 関連度の低い情報から推論で埋めることを
   禁じ、そういう回答は wiki に還元しない。gist のコメント欄で報告された最大の失敗は、
   自信のある捏造がページ化され、それ自体が出典になることだった
3. **全ページに対象バージョンと取得日を必須にする。** ゲーム仕様は腐る
4. **AI が踏みやすい誤りを明示的に書く。** Wiki を読めば分かることの転記は検索で代替できる。
   既定の挙動を訂正する情報のほうに価値がある
5. **wiki に書く数値・引用は `raw/` の中に同じ形で存在させる。** Astro-Han の実装が
   Grounding Invariant と呼んでいる規則で、`raw/` を不変にする理由でもある。書く前に
   raw を検索して確かめ、確かめられない値は精度を落とすか書かない

## 限界

LLM Wiki パターン自体が 2026 年 4 月発で、長期運用の知見はまだ蓄積途上にある。
gist も「この文書は意図的に抽象的であり、具体はドメインと好みに依存する」と断っている。

[^1]: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
[^2]: https://github.com/Astro-Han/karpathy-llm-wiki
