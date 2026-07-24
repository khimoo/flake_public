# Obsidian 設定（`.obsidian`）の配布と config/notes の repo 分離（設計判断）

Obsidian vault（Zettelkasten）の `.obsidian`（設定 + community plugin 本体）を、fresh マシンでも
「clone してそのまま動く」状態に配布し、かつ **config の変更は共有 repo・ノートの変更は private repo**
で追える形にするための構成。

添付・papis の Drive 同期は [zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md) を参照
（`.obsidian` 設定はそれとは別系統で、Drive ではなく git に載る）。使い方は
[../howtouse/zettelkasten-obsidian-config.md](../howtouse/zettelkasten-obsidian-config.md) を参照。

## config の live な source-of-truth は vault、共有 repo は派生スナップショット

`.obsidian`（`workspace.json` 等の可変ファイルを除く）は private notes repo `khimoo/zettelkasten` に
tracked で、`obsidian-git` の vault 同期に相乗りしている。これが desktop ↔ spin713 の**生きた設定同期**を
担う。public repo `khimoo/zettelkasten-workflow` は、そこからの**派生スナップショット**として同じ
`.obsidian` を持つ（flake が `github:` で eval 時に取り込めるよう、public 側に実体が要る）。

つまり source-of-truth は 2 つの向きの道具で保たれる:

- **seed-obsidian（public → vault、非破壊配布）**: fresh マシンで vault に `.obsidian` が無いときだけ、
  public のスナップショットをコピーする。既存の live 設定は上書きしない（seed-once）。
- **mirror-obsidian（vault → public、派生更新）**: vault の live 設定が変わったら、tracked な
  `.obsidian` を public repo へコピーして commit する。「たまに手で」実行して派生を追従させる。

seed が bootstrap、mirror が更新で、対の向き。live 同期そのものは引き続き `obsidian-git`（vault repo）が担い、
mirror はその结果を共有 repo へ写すだけ。

## sanitize = vault の `.gitignore`（tracked 集合がミラー対象）

mirror がコピーするのは vault で **git-tracked な `.obsidian`** だけ（`git ls-files .obsidian`）。何を公開して
よいかの判断は、各自の `.gitignore` に集約される。現状 vault が除外しているのは:

- `.obsidian/workspace.json` / `workspace-mobile.json`（レイアウト・開いていたノート＝ per-machine state）
- `.obsidian/plugins/realclaudian/data.json`（トークン等を持ちうる plugin state）

これは **denylist**（列挙して落とす）なので、無人で公開すると危うい。将来あるプラグインが tracked な
`data.json` に機密を書き込めば、次の mirror で public に流れうる。そのため mirror は **auto-push しない**
——commit 止まりにして、push 前の `git diff` を人間の漏洩ゲートにする。tracked 集合が空なら、誤って dest の
設定を消さないよう mirror は中止する。

## commit 先のパラメータ化＝ fork フレンドリー

mirror-obsidian は source（vault）と dest（config repo）を引数/環境変数で受け取り、**owner をハードコード
しない**。fork した第三者は自分の dest を渡すだけで同じ機構を使える（`nix run github:<fork>#mirror-obsidian
-- <vault> <dest>`）。私固有の既定 dest は flake_public の settings（`obsidianConfigRepo`）だけに閉じ、
`modules/home-manager/zettelkasten.nix` が `services.zettelkasten.obsidian.mirrorRepo` に注入する。

同期（rclone/gdrive/sops）が single-tenant（個人の Drive・受信者鍵に縛られ、fork では secret 差し替え）
なのに対し、config ミラーは **secret を一切触らない**（`.obsidian` は暗号化しない公開設定）ので多テナント化
してよい。「config 分割は fork フレンドリー、同期は fork-and-replace」と役割で切れる。

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
別 repo に保てる。代償は「public は mirror するまで古い」点だが、config は頻繁に変わらないので許容する。

## 運用上の性質・既知の制約

- **public は派生で、mirror するまで stale**。fresh マシンの seed が古い設定を配りうる。config を大きく
  変えたら mirror する。
- **denylist の穴**。新規プラグインが tracked な `data.json` に機密を書くと mirror で public に流れうる。
  mirror（＝ push）前に `--dry-run` / `git diff` で確認し、必要なら vault の `.gitignore` に足す。
- **mirror は tracked 集合が空なら中止**（誤削除防止）。vault で `.obsidian` を add していないと動かない。
- **live な設定同期は `obsidian-git`（vault repo）が担う**。mirror はマシン間同期の代替ではない。
