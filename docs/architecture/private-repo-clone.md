# private repo の宣言的 clone（設計判断）

使い方は [docs/howtouse/private-repo-clone.md](../howtouse/private-repo-clone.md) を参照。
実装: [modules/home-manager/private-repos.nix](../../modules/home-manager/private-repos.nix)。

> **今後の方向性**: age 鍵の bootstrap 経路（現在「SSH 送信 or Bitwarden から取得」の
> 2 経路併存）は [new-machine.md](./new-machine.md) の nixos-anywhere ベース 1 コマンド
> プロビジョニングに一本化する予定。silent skip も strict 化で撤廃する。

## 何を解決するか

新しい環境へ flake を適用するとき、従来は private repo を手で `git clone` する必要がある。
これを無くし、switch するだけで clone される状態にしたい。対象は NixOS だけでなく
非 NixOS（WSL / macOS）も含む。対象 repo は 1 つに限定せず、Claude 設定と Obsidian
workflow など複数の private repo を **同じ経路** で自動化する。

## なぜ home-manager 単独か

以前は「各マシンのホスト鍵で無人復号する NixOS systemd サービス」で組んでいたが、破棄した。
理由:

- ホスト鍵（`/etc/ssh/ssh_host_ed25519_key`）は root しか読めず、home-manager
  （ユーザー権限）から扱えない。NixOS 専用になり、WSL / macOS を切り捨てる
- 復号の種を「ユーザーが読める専用 age 鍵」にすれば root 不要になり、
  NixOS / 非 NixOS を同じ経路で扱える

`home.activation`（`entryAfter [ "writeBoundary" ]`）は `home-manager switch` でも
`nixos-rebuild switch`（統合された home-manager）でも走り、systemd に依存しないので
Darwin でも動く。これで全環境を 1 実装に統一した。

## 認証の流れ

1. **復号の種 = 専用 age 鍵 1 本**。`~/.config/sops/age/keys.txt` に out-of-band で置く
   （既存マシンから SSH 送信、または Bitwarden から取得）
2. **暗号文 = GitHub 登録済みのユーザー SSH 鍵**（既存のものを流用）を sops で暗号化し
   `secrets/secrets.yaml` にコミット。activation が age 鍵で復号し、`~/.ssh/id_ed25519` が
   無ければ書き出す
3. その SSH 鍵で clone する

新しい read-write 鍵を発行して GitHub に登録し直す手間を避けるため、既存のユーザー鍵を
そのまま暗号文に載せた。

## age 鍵 1 本に統一した理由

以前案は「admin 編集鍵 + 各ホスト鍵」の複数受信者だったが、専用 age 鍵 1 本に集約した。
同じ鍵が復号の種（全環境の `keys.txt`）と暗号文の編集鍵を兼ねる。

- マシン追加のたびの受信者追加・`sops updatekeys`（再暗号化）が要らなくなる
- Bitwarden に 1 本置くだけで、どの新環境でも同じ手順で復元できる

代償は粒度: 1 台漏れると同じ鍵で全暗号文が復号できる。個人の 2〜3 台構成では、
Bitwarden 保管 + 漏洩時の rotate（age 鍵を作り直し `sops updatekeys` で全体を再暗号化）で
実用上妥当と判断した。台数・共有者が増えるなら per-machine 受信者へ戻す。

## clone-if-absent（冪等・非破壊）

各 `{ url, dest }` について `dest` が存在しないときだけ clone する。SSH 鍵も
`~/.ssh/id_ed25519` が無いときだけ書き出す。

- 既に clone / 鍵設置済みなら何もしない（毎 switch で pull・上書きしない）
- live に編集する working tree・既存の鍵を Nix が破壊しない

「初回だけ面倒を見て、以降の pull/push はユーザーに委ねる」割り切り。mutable な状態を
immutable に管理しようとしない（[claude-config.md](./claude-config.md) の out-of-store
symlink と同じ思想）。

## 複数 repo へ汎用化

`private-repos.nix` は `settings.privateRepos = [{ url; dest; }]` を回して clone する。
リストは `flake.nix` が高レベル設定（`claudeConfigRepo` / `obsidianConfigRepoUrl` などの
URL 側と、`claudeConfigRoot` / `obsidianConfigRepo` などの dest 側）から自動で組み立てる。
これで新しい private repo を足すときも `private-repos.nix` は触らず、`flake.nix` の
`buildPrivateRepos` に 1 行追加するだけで済む。

## vault フォルダの所有者は clone

Obsidian vault（ノート本文の private repo）もこのリストに載せている。vault を用意する経路は
もう一つあり、`services.zettelkasten.initializeVault`（外部 flake 側の option）が switch 中に
フォルダ作成と `git init` を行う。**両方を有効にしてはいけない**——先に空フォルダができると
`git clone` が「空でないディレクトリ」で失敗するため。

この repo では clone 側に一本化した。ノート本文が既に GitHub にある以上、`git init` は
初期化ではなく衝突でしかない。`initializeVault` は既定 `false` なので、明示的に何も書かない
ことが正しい設定になる。

同じ理由で、vault の中へ mount する btrfs subvol（papis ライブラリ）も clone より先に
mount 先を作ってはいけない。これは `fileSystems` ではなく条件付き `systemd.mounts` で
表現している（[disk-tiering.md](./disk-tiering.md) 参照）。

## 抜き差し可能性

URL 側（`claudeConfigRepo` / `obsidianConfigRepoUrl` 等）が `null`（既定）ならその repo は
リストに入らず、全 URL が null なら activation も secret 参照も生えない。
dest 側とは別軸で持つことで「symlink（あるいは mirror-obsidian）だけ欲しい（手動 clone）」と
「clone も自動化したい」を repo ごとに独立に選べる。

## ゼロからの復元（eval 時の鍵依存は解消済み）

以前は fresh 環境で flake の評価自体に `~/.ssh/id_ed25519` が必要だった。`inputs.zettelkasten`
を `git+ssh://` で取得していたため、鍵が無いと switch に到達する前の eval で失敗し、「age 鍵だけ
渡せば完全にゼロから復元」は成立しなかった。

この制約は zettelkasten の mechanism を public repo（`github:khimoo/zettelkasten-workflow`）へ
分割し、input を `github:`（https 取得）に切り替えたことで**解消した**
（[zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md) 参照）。eval が SSH 鍵を
要求しなくなったので、いまは:

- **専用 age 鍵 1 本を `~/.config/sops/age/keys.txt` に置く**（既存マシンから SSH 送信、または
  Bitwarden から取得）
- 公開 flake を clone して switch する

だけでゼロから復元できる。SSH 鍵（`~/.ssh/id_ed25519`）は switch 中の activation が
`secrets.yaml` を age 鍵で復号して書き出すので、事前に置かなくてよい。

## 限界

- `secrets/secrets.yaml` が無いまま URL 側（`claudeConfigRepo` / `obsidianConfigRepoUrl` 等）を
  指定すると、そのホストの eval で失敗する（activation が secret を store path として
  参照するため）。全 URL 未指定なら参照されないので、公開 flake の `nix flake check` は壊れない
