# vault の骨格の配布と config/notes の repo 分離（設計判断）

Obsidian vault（Zettelkasten）の**骨格**——分類フォルダ、運用ドキュメント、`.obsidian`（設定 +
community plugin 本体）、`.claude/skills/`——を、**骨格の変更は public repo・ノートの変更は
private repo** で追える形にするための構成。

添付・papis の Drive 同期は [zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md) を参照
（骨格はそれとは別系統で、Drive ではなく git に載る）。使い方は
[../howtouse/zettelkasten-vault-skeleton.md](../howtouse/zettelkasten-vault-skeleton.md) を参照。

## live な source-of-truth は vault、public repo は派生スナップショット

骨格（`workspace.json` 等の可変ファイルを除く）は private notes repo `khimoo/zettelkasten` に
tracked で、`obsidian-git` の vault 同期に相乗りしている。これが desktop ↔ spin713 の**生きた同期**を
担う。public repo `khimoo/zettelkasten-workflow` は、そこからの**派生スナップショット**として同じ
骨格を `skeleton/` に持つ（flake が `github:` で eval 時に取り込めるよう、public 側に実体が要る）。

向きの違う 2 つの道具で保つ:

- **seed-vault（public → vault、非破壊配布）**: vault に無いものだけコピーする。既存は上書きしない。
- **mirror-vault（vault → public、派生更新）**: vault の骨格を public repo の `skeleton/` へ写して
  commit する。「たまに手で」実行して派生を追従させる。

live 同期そのものは引き続き `obsidian-git`（vault repo）が担い、mirror はその結果を public へ写すだけ。

## seed が実際に配るのは vault をゼロから作る環境だけ

この repo の運用では、vault は private notes repo の clone で用意する（`private-repos.nix`）。
clone は骨格を丸ごと連れてくるので、**seed はほぼ skip する**。activation の順序に関わらず結果は
同じで、clone より先に走れば vault 未存在で skip、後に走れば既存で skip する。

したがって public スナップショットが実際にコピーされるのは、`initializeVault = true` で vault を
ゼロから作る環境だけである。この非対称を明示しておかないと、「新しいマシンを立てる前に mirror して
push する」という不要な手順を運用に持ち込む。**mirror の契機は骨格の変更であって、マシン追加ではない。**

それでも seed 経路を残しているのは、これが public repo としての入口——骨格を持たない人が
`initializeVault = true` だけで動く状態に到達できる——であり、同時に vault repo を失ったときの
復元路でもあるため。維持コストは mirror をたまに回すことだけに収まる。

## seed の粒度は 2 通りある

運ぶ物の性質が違うので、「無ければ置く」の単位を揃えていない。

- **`.obsidian` はディレクトリ単位**。既にあれば丸ごと触らない。Obsidian 自身が常時書き換える
  自己整合的な状態なので、ファイル単位で差し込むと、利用者が無効化したプラグインを
  `community-plugins.json` 経由で復活させる事故が起きる。
- **それ以外はファイル単位**。「`CLAUDE.md` だけ既にある」「`Templates/` は空」が普通に起きるので、
  ディレクトリ単位にすると片方が既にあるだけで全部配られなくなる。

代償として、public 側の骨格に新しいファイルが増えると、既存 vault にもそれだけが降ってくる。
骨格に足す判断は「全 vault に配ってよいか」で行う。

## 配るものの選び方は 2 通り

`.obsidian` は **denylist**、骨格は **allowlist**。逆にしているのは、間違えたときにどちらへ倒れるかが
違うため。

`.obsidian` は Obsidian が勝手にファイルを増やすので、列挙すると追随できない。よって
`git ls-files .obsidian`（vault が tracked にした集合）を取り、そこから配ってはいけないものを引く。
sanitize は 2 段で、1 段目は vault の `.gitignore`（`workspace.json` / `workspace-mobile.json` と
`plugins/realclaudian/data.json` はここで落ちる）、2 段目が `mirror-vault`（配布の境界）。

2 段目が要るのは、「vault では同期したいが公開はしたくない」ものが存在するため。vault 側で untrack
すれば公開はされないが、desktop ↔ spin713 の同期からも外れてしまう。両立させる場所が配布の境界しかない。

- `bookmarks.json` / `workspaces.json` — 自分のノートへの参照と名前付きレイアウト。**削除して配る**
  （Obsidian が必要時に作る）。環境依存の判断ではないので option にせず固定にしてある。
- typst plugin — WSL の Obsidian を native assertion で落とし、26MB の wasm を持ち込む。プラグイン本体と
  `community-plugins.json` の id の両方から除く（本体だけ消すと Obsidian が不在のプラグインを読もうとする）。
  これは「WSL では壊れる」という環境依存の判断なので `excludedPlugins` option になっている。
- `obsidian-git` の `autoPullOnBoot` — remote を持たない配布先 vault では起動ごとにエラー通知が出る。

骨格の方は逆で、vault が tracked にしているものの大半（`Zettel/` `Dailies/` `Goals/` …）が個人の
ノートである。全 tracked を写すと private が public へ流れ込むので、配ると決めたものだけを
`nix/skeleton-paths.nix` に列挙する。足し忘れは「配り漏れ」で済み、漏洩にはならない。列挙したものが
vault に無ければ mirror は中止する——黙って落とすと、直後の `rsync --delete` が repo 側からも消す。

denylist 側は無人で公開すると危うい。将来あるプラグインが tracked な `data.json` に機密を書き込めば、
次の mirror で public に流れうる。そのため mirror は **auto-push しない**——commit 止まりにして、
push 前の `git diff` を人間の漏洩ゲートにする。tracked 集合が空なら、誤って dest の設定を消さないよう
mirror は中止する。

## dest はパラメータ化する（owner をハードコードしない）

`mirror-vault` は source（vault）と dest（config repo）を引数/環境変数で受け取る。自分の骨格を
配りたい人は、自分の vault と dest を渡すだけでよい。私固有の既定 dest は flake_public の
settings（`vaultSkeletonRepo`）だけに閉じ、`modules/home-manager/zettelkasten.nix` が
`services.zettelkasten.mirrorRepo` に注入する。

パラメータ化の理由は第三者の存在ではなく**結合度**にある。dest を焼き込むと mechanism 側が特定の環境の
パス（共通結合）を知ることになる。引数で受ければデータ結合に落ちる。この repo の第一の利用者は
flake_public 自身なので、その意味でも注入する形が正しい。

同期（rclone/gdrive）が single-tenant（個人の Drive に縛られる）なのに対し、骨格のミラーは secret を
一切触らない（公開してよい設定とドキュメントだけ）ので、誰の環境でもそのまま動く。

## feature は「同期に依存するか」で切る

flake_public 側の `features.obsidian` が gate するのは Obsidian 本体の導入と `.obsidian` の seed だけで、
骨格の seed は `services.zettelkasten.enable`（同期 feature でも立つ）側に載っている。骨格は Obsidian
固有ではなく vault の中身なので、Obsidian を入れないマシンでも配られてよい、という切り方。

## 検討して退けた案: source-of-truth を public 側へ移す

「骨格は public repo で追う」を、mirror（派生）でなく **source-of-truth ごと public へ移す**形でも実現できる。
2 つ検討して退けた。

- **symlink 方式**: vault の `.obsidian` を public repo のローカル checkout へ out-of-store symlink で張り
  （nvim/wezterm/Claude 設定と同じ発想。[claude-config.md](./claude-config.md)）、Obsidian の書き込みを直接
  public の working tree に落とす。しかしこれは `obsidian-git` が設定も込みで**自動同期している現状の
  利点を捨てる**ことになる。source を public（手編集の flake repo）へ移すと、マシン間の同期が
  手動 commit/pull へ退行する。加えて各マシンに public checkout が必須になり、clone→symlink の順序依存、
  private からの untrack で他マシンの設定が消える移行の段取りが要る。
- **同居方式**: notes と flake を 1 repo にまとめ、`nix run` で flake + 骨格を public へ export する。
  source-of-truth は 1 つになるが、`obsidian-git` の auto-commit と flake の deliberate commit が同じ repo で
  衝突し、flake の履歴・コミットメッセージが濁る。

採ったのは **split 維持 + mirror**。`obsidian-git` の自動同期をそのまま活かし、たまに mirror で
public を追従させる。auto-commit（notes）と deliberate commit（flake / 骨格スナップショット）の履歴を
別 repo に保てる。代償は「public は mirror するまで古い」点だが、seed の受益者が限られるので許容する。

## 運用上の性質・既知の制約

- **public は派生で、mirror するまで stale**。実測では mirror の翌日には数ファイル乖離する。ただし stale が
  害になるのは seed される環境だけで、この repo のホストはほぼ該当しない。
- **反映には消費側の `nix flake update` が要る**。input は `flake.lock` に pin されているので、mirror して
  push しただけでは store のスナップショットは古いままになる。
- **denylist の穴**。新規プラグインが tracked な `data.json` に機密を書くと mirror で public に流れうる。
  push 前に `--dry-run` / `git diff` で確認し、必要なら vault の `.gitignore` か配布境界に足す。
- **allowlist の食い違いで mirror は止まる**。`nix/skeleton-paths.nix` に列挙したファイルを vault から
  消したり改名したりすると、次の mirror が中止する（誤削除防止）。
- **live な同期は `obsidian-git`（vault repo）が担う**。mirror はマシン間同期の代替ではない。
