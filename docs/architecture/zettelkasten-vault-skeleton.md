# vault の骨格の設計

使い方: [vault の骨格の配布とミラー](../howtouse/zettelkasten-vault-skeleton.md)
実装: [zettelkasten.nix](../../modules/home-manager/zettelkasten.nix)、mechanism は zettelkasten-workflow（`seed-vault`、`mirror-vault`、`nix/skeleton-paths.nix`）

Obsidian vault の骨格（分類フォルダ、運用ドキュメント、`.obsidian`、skills へのリンク）の変更は public repo で、ノートの変更は private repo で追えるようにする。
添付と papis の Drive 同期は別の仕組み（[zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md)）で、骨格は Drive ではなく git に載る。

## 正本は vault で、public repo はその写し

骨格は private の notes repo（`khimoo/zettelkasten`）で追跡し、`obsidian-git` の同期で desktop と spin713 の間を運ぶ。
public repo（`khimoo/zettelkasten-workflow`）は同じ骨格を `skeleton/` に持つ写しで、flake が `github:` で評価時に取り込めるよう、public の側に実体が要る。

- `mirror-vault`（vault から public へ）: vault の骨格を `skeleton/` に写して commit する。たまに手で実行する
- `seed-vault`（public から vault へ）: vault にないものだけをコピーする。既存のものは上書きしない

## clone した vault には seed しない

この環境の vault は notes repo の clone で用意し、中身は notes repo のものとする。
`initializeVault = false` を明示し、seed の activation そのものを生成しない。
「既存を上書きしない」だけでは、消したファイルとまだ配っていないファイルを区別できず、わざと消したファイルも戻すため。
2026-10-20 には、notes repo で消した旧骨格の 11 件が、次の Home Manager の activation で戻ってコミットされた。当時の workflow（`8eb6bb3`）は `initializeVault = false` でも seed を生成していた。
修正版（`18bd225`）に加え、`vault-seed-isolation` のチェックで desktop と spin713 の設定が seed を生成しないことを確かめ、利用側の assertion でも seed の activation を拒む。古い workflow に戻っても、適用する前に止まる。

そのため public の写しが実際に配られるのは、`initializeVault = true` で vault をゼロから作る環境だけで、mirror する契機は骨格を変えたときで、マシンを足したときではない。
seed の経路を残すのは、骨格を持たない人が `initializeVault = true` だけで動く状態にできる入口で、vault repo を失ったときの復元の手段でもあるため。

## seed の単位は 2 通り

`.obsidian` はディレクトリごとに扱い、すでにあれば触らない。Obsidian が常に書き換える状態なので、ファイル単位で足すと、利用者が無効にしたプラグインを `community-plugins.json` 経由で戻してしまう。
それ以外はファイル単位で足す。「`CLAUDE.md` だけある」「`Templates/` が空」がよく起きるので、ディレクトリ単位では片方があるだけで全部配られなくなる。

## 配るものの選び方は 2 通り

`.obsidian` は除外のリスト（denylist）で、骨格は許可のリスト（allowlist）で選ぶ。間違えたときにどちらへ倒れるかが違うため。

`.obsidian` は Obsidian がファイルを増やすので、列挙では追いつけない。`git ls-files .obsidian`（vault が追跡するもの）から配らないものを引く。
除外は 2 段で、vault の `.gitignore` と、`mirror-vault`（配る境界）がある。vault では同期したいが公開したくないもの（`bookmarks.json`、`workspaces.json`）は、vault で追跡から外すとマシン間の同期からも外れるので、配る境界で消すしかない。
typst のプラグインは WSL の Obsidian を落とし、26MB の wasm を持ち込む。環境による判断なので `excludedPlugins` のオプションにし、本体と `community-plugins.json` の id の両方から除く（本体だけ消すと、Obsidian がないプラグインを読もうとする）。

骨格は、vault が追跡するものの多く（`Zettel/`、`Dailies/`、`Goals/`）が個人のノートなので、全部を写すと private が public に流れる。配ると決めたものだけを `nix/skeleton-paths.nix` に並べる。書き忘れは配り漏れで済み、漏洩にはならない。
並べたものが vault になければ mirror を止める。黙って落とすと、直後の `rsync --delete` が repo の側からも消す。

除外のリストのほうは、無人で公開すると危うい。プラグインが追跡対象の `data.json` に秘密を書くと、次の mirror で public に流れる。
そのため mirror は commit で止め、push する前の `git diff` を人が確かめる。追跡しているものが空なら、写し先の設定を消さないよう mirror を止める。

## 写し先は引数で受け取る

`mirror-vault` は vault と写し先を引数か環境変数で受け取り、owner を書き込まない。
自分の写し先はユーザーのオプション `local.profile.vaultSkeletonRepo` にだけ置き、`zettelkasten.nix` が `services.zettelkasten.mirrorRepo` に渡す。
写し先を mechanism に書き込むと、mechanism が特定の環境のパスを知ることになる。骨格の写しは秘密を扱わないので、誰の環境でもそのまま動く。

## 正本を public に移す案は退けた

- vault の `.obsidian` を public repo の checkout へ symlink する: `obsidian-git` が設定ごと自動で同期している利点を失い、マシン間の同期が手での commit と pull に戻る。各マシンに public の checkout が要り、clone と symlink の順序や、private から追跡を外したときに他のマシンの設定が消える移行も要る
- notes と flake を 1 つの repo にまとめる: `obsidian-git` の自動 commit と flake の手での commit が同じ repo でぶつかり、flake の履歴が濁る

代償として、public の写しは mirror するまで古い（mirror の翌日に数ファイル食い違っていた）。clone した vault には seed しないので、普段の同期は影響を受けない。
写しを push しても、取り込む側は `flake.lock` の `zettelkasten` を更新するまで古いまま。
