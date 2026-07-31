# Obsidian 設定（`.obsidian`）の配布と config/notes の repo 分離（設計判断）

Obsidian vault（Zettelkasten）の `.obsidian`（設定 + community plugin 本体）を、**config の変更は
public repo・ノートの変更は private repo** で追える形にするための構成。

添付・papis の Drive 同期は [zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md) を参照
（`.obsidian` 設定はそれとは別系統で、Drive ではなく git に載る）。使い方は
[../howtouse/zettelkasten-obsidian-config.md](../howtouse/zettelkasten-obsidian-config.md) を参照。

## live な source-of-truth は vault、public repo は派生スナップショット

`.obsidian`（`workspace.json` 等の可変ファイルを除く）は private notes repo `khimoo/zettelkasten` に
tracked で、`obsidian-git` の vault 同期に相乗りしている。これが desktop ↔ spin713 の**生きた設定同期**を
担う。public repo `khimoo/zettelkasten-workflow` は、そこからの**派生スナップショット**として同じ
`.obsidian` を持つ（flake が `github:` で eval 時に取り込めるよう、public 側に実体が要る）。

向きの違う 2 つの道具で保つ:

- **seed-obsidian（public → vault、非破壊配布）**: vault に `.obsidian` が無いときだけ、public の
  スナップショットをコピーする。既存の live 設定は上書きしない（seed-once）。
- **mirror-obsidian（vault → public、派生更新）**: vault の tracked な `.obsidian` を public repo へ
  写して commit する。「たまに手で」実行して派生を追従させる。

live 同期そのものは引き続き `obsidian-git`（vault repo）が担い、mirror はその結果を public へ写すだけ。

## seed が実際に配るのは vault をゼロから作る環境だけ

この repo の運用では、vault は private notes repo の clone で用意する（`private-repos.nix`）。
clone は tracked な `.obsidian` を 40 ファイル余り連れてくるので、**seed は必ず skip する**。
activation の順序に関わらず結果は同じで、clone より先に走れば vault 未存在で skip、後に走れば
`.obsidian` 存在で skip する。

したがって public スナップショットが実際にコピーされるのは、`initializeVault = true` で vault を
ゼロから作る環境だけである。この非対称を明示しておかないと、「新しいマシンを立てる前に mirror して
push する」という不要な手順を運用に持ち込む。**mirror の契機は設定変更であって、マシン追加ではない。**

それでも seed 経路を残しているのは、これが public repo としての入口——`.obsidian` を持たない人が
`initializeVault = true` だけで動く状態に到達できる——であり、同時に vault repo を失ったときの
`.obsidian` の復元路でもあるため。維持コストは mirror をたまに回すことだけに収まる。

## sanitize は 2 段

1. **vault の `.gitignore`**。mirror がコピーするのは vault で git-tracked な `.obsidian` だけ
   （`git ls-files .obsidian`）。`workspace.json` / `workspace-mobile.json`（per-machine のレイアウト）と
   `plugins/realclaudian/data.json`（トークンを持ちうる plugin state）はここで落ちる。
2. **`mirror-obsidian`（配布の境界）**。vault では tracked にしたいが配ってはいけないものを落とす。

2 段目が要るのは、「vault では同期したいが公開はしたくない」ものが存在するため。vault 側で untrack
すれば公開はされないが、desktop ↔ spin713 の同期からも外れてしまう。両立させる場所が配布の境界しかない。

- `bookmarks.json` / `workspaces.json` — 自分のノートへの参照と名前付きレイアウト。**削除して配る**
  （Obsidian が必要時に作る）。環境依存の判断ではないので option にせず固定にしてある。
- typst plugin — WSL の Obsidian を native assertion で落とし、26MB の wasm を持ち込む。プラグイン本体と
  `community-plugins.json` の id の両方から除く（本体だけ消すと Obsidian が不在のプラグインを読もうとする）。
  これは「WSL では壊れる」という環境依存の判断なので `excludedPlugins` option になっている。
- `obsidian-git` の `autoPullOnBoot` — remote を持たない配布先 vault では起動ごとにエラー通知が出る。

どちらの段も **denylist**（列挙して落とす）なので、無人で公開すると危うい。将来あるプラグインが tracked な
`data.json` に機密を書き込めば、次の mirror で public に流れうる。そのため mirror は **auto-push しない**
——commit 止まりにして、push 前の `git diff` を人間の漏洩ゲートにする。tracked 集合が空なら、誤って dest の
設定を消さないよう mirror は中止する。

## dest はパラメータ化する（owner をハードコードしない）

`mirror-obsidian` は source（vault）と dest（config repo）を引数/環境変数で受け取る。自分の `.obsidian` を
config repo として配りたい人は、自分の vault と dest を渡すだけでよい。私固有の既定 dest は flake_public の
settings（`obsidianConfigRepo`）だけに閉じ、`modules/home-manager/zettelkasten.nix` が
`services.zettelkasten.obsidian.mirrorRepo` に注入する。

パラメータ化の理由は第三者の存在ではなく**結合度**にある。dest を焼き込むと mechanism 側が特定の環境の
パス（共通結合）を知ることになる。引数で受ければデータ結合に落ちる。この repo の第一の利用者は
flake_public 自身なので、その意味でも注入する形が正しい。

同期（rclone/gdrive）が single-tenant（個人の Drive に縛られる）なのに対し、config ミラーは secret を
一切触らない（`.obsidian` は暗号化しない公開設定）ので、誰の環境でもそのまま動く。

## 検討して退けた案: config の source-of-truth を public 側へ移す

「設定は public repo で追う」を、mirror（派生）でなく **source-of-truth ごと public へ移す**形でも実現できる。
2 つ検討して退けた。

- **symlink 方式**: vault の `.obsidian` を public repo のローカル checkout へ out-of-store symlink で張り
  （nvim/wezterm/Claude 設定と同じ発想。[claude-config.md](./claude-config.md)）、Obsidian の書き込みを直接
  public の working tree に落とす。しかしこれは `obsidian-git` が config も込みで**自動同期している現状の
  利点を捨てる**ことになる。config source を public（手編集の flake repo）へ移すと、マシン間の config 同期が
  手動 commit/pull へ退行する。加えて各マシンに public checkout が必須になり、clone→symlink の順序依存、
  private からの `.obsidian` untrack で他マシンの config が消える移行の段取りが要る。
- **同居方式**: notes と flake を 1 repo にまとめ、`nix run` で flake + `.obsidian` を public へ export する。
  source-of-truth は 1 つになるが、`obsidian-git` の auto-commit と flake の deliberate commit が同じ repo で
  衝突し、flake の履歴・コミットメッセージが濁る。

採ったのは **split 維持 + mirror**。`obsidian-git` の自動同期（config 含む）をそのまま活かし、たまに mirror で
public を追従させる。auto-commit（notes）と deliberate commit（flake / config スナップショット）の履歴を
別 repo に保てる。代償は「public は mirror するまで古い」点だが、seed の受益者が限られるので許容する。

## 運用上の性質・既知の制約

- **public は派生で、mirror するまで stale**。実測では mirror の翌日には数ファイル乖離する。ただし stale が
  害になるのは seed される環境だけで、この repo のホストは該当しない。
- **反映には消費側の `nix flake update` が要る**。input は `flake.lock` に pin されているので、mirror して
  push しただけでは store のスナップショットは古いままになる。
- **denylist の穴**。新規プラグインが tracked な `data.json` に機密を書くと mirror で public に流れうる。
  push 前に `--dry-run` / `git diff` で確認し、必要なら vault の `.gitignore` か配布境界に足す。
- **mirror は tracked 集合が空なら中止**（誤削除防止）。vault で `.obsidian` を add していないと動かない。
- **live な設定同期は `obsidian-git`（vault repo）が担う**。mirror はマシン間同期の代替ではない。
