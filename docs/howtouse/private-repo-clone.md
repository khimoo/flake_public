# SSH 鍵の配布と private repo の clone（home-manager・age 鍵 1 本）

新しい環境に flake を適用したとき、**手作業を age 鍵 1 本の設置と `clone-repos` の実行だけ**にする運用。
SSH 鍵（GitHub 認証用と LAN 用）は switch が書き出し、private repo（ノート本文・
Claude 設定・Obsidian workflow）は switch の後に `clone-repos` が clone する。switch はネットワークから
取得しない。NixOS でも 非 NixOS（macOS）でも同じ経路（home-manager の `home.activation` とコマンド）で動く。会社PCの nixos-work-wsl は
age 鍵を置かないので、この仕組みを使わない（[wsl.md](./wsl.md)）。

設計判断は [docs/architecture/private-repo-clone.md](../architecture/private-repo-clone.md) を参照。

## 仕組みの概要

- 各環境に置く秘密は **専用 age 鍵 1 本だけ**（`~/.config/sops/age/keys.txt`）。
  これを新環境へ渡す手段は 2 つ:
  - 既存マシンから SSH でファイルを送る
  - Bitwarden から取り出す
- SSH 秘密鍵を **sops で暗号化して `secrets/secrets.yaml` にコミット**する。
  暗号文なので公開 repo でも安全。中身は 2 本:

  | secret のキー | 書き出し先 | 用途 |
  |---|---|---|
  | `git_ssh_key` | `~/.ssh/id_github` | GitHub 認証（clone / push） |
  | `lan_ssh_key` | `~/.ssh/id_lan` | LAN 内 machine-to-machine（[machine-ssh.md](./machine-ssh.md)） |

- `home.activation` が switch のたびに、`secrets.yaml` を age 鍵で復号し、宣言した鍵ファイルを暗号文の内容に揃える。
  **age 鍵が無い / 復号に失敗した場合は警告ではなく error で停止する**（switch が失敗する）。
  「switch は成功したのに鍵が無い」状態を作らないため。
- `clone-repos` が、`local.profile.privateRepos` の各 `{ url, dest }` について、`dest` が無ければ
  `id_github` で clone する。`id_github` が無ければ git を呼ばずに止まる。`clone-repos --dry-run` は
  clone する予定の repo を表示するだけにする。

  既存Git checkoutは触らない（上書き・pullしない）。Git checkoutでないdestが既にある場合はその repo を失敗として報告し、残りは続ける。中身を確認し、手動で移すか正しいcheckoutを指定して再実行する。新規cloneの途中失敗は一時領域を掃除するため、そのまま再実行できる。

鍵配布はユーザーごとに決まる。clone対象があれば `id_github`、`local.profile.lanSsh = true` なら `id_lan` を配る。既存2台のpomuは両方を選んでいる。新規ユーザーには既定でどちらも配らない。

`local.profile.privateRepos` は `modules/home-manager/profile.nix` が高レベル設定
（`agentConfigRepo` / `vaultSkeletonRepoUrl` など、URL 側の設定）から組み立てる。
URL 側が `null` の項目は落とされるので、dest 側だけ指定すればその repo は手動 clone 運用に
留まる。

## 初回セットアップ

repo に受信者（`.sops.yaml` の `&deploy`）と暗号文（`secrets/secrets.yaml`）が揃っていれば
この節は済んでいる。ゼロから立ち上げるとき、または [age 鍵を作り直すとき](#age-鍵を作り直す)
にここへ戻る。

### 1. 専用 age 鍵を作る

```sh
mkdir -p ~/.config/sops/age
( umask 077; nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/keys.txt )
```

- 出力の `Public key: age1...` を控える（次の手順で `.sops.yaml` に入れる）
- `keys.txt`（`AGE-SECRET-KEY-...` を含む）は **Bitwarden に保管**し、
  各環境の `~/.config/sops/age/keys.txt` に置く。**公開 repo にはコミットしない**

### 2. `.sops.yaml` の recipient を設定する

リポジトリ直下の [.sops.yaml](../../.sops.yaml) の `&deploy` の値を 1. の公開鍵にする。

### 3. SSH 鍵を用意する

GitHub 用の鍵が手元に無ければ作って GitHub に登録する:

```sh
ssh-keygen -t ed25519 -C "$(hostname)" -f ~/.ssh/id_github
gh ssh-key add ~/.ssh/id_github.pub --title "$(hostname) $(date +%F)"
```

LAN 用の共通鍵も作る（passphrase なし。無人で使うため）:

```sh
ssh-keygen -t ed25519 -C pomu@lan -f ~/.ssh/id_lan -N ''
```

`~/.ssh/id_lan.pub` の内容を `hosts/machines.nix` の `lanPublicKey` に入れる。

### 4. 両方を暗号化してコミット

エディタを開かず、平文を端末に出さずに暗号化する:

```sh
tmp=$(mktemp -p "$XDG_RUNTIME_DIR"); chmod 600 "$tmp"
{ echo 'git_ssh_key: |'; sed 's/^/  /' ~/.ssh/id_github;
  echo 'lan_ssh_key: |'; sed 's/^/  /' ~/.ssh/id_lan; } > "$tmp"
nix shell nixpkgs#sops -c sops --encrypt --filename-override secrets/secrets.yaml \
  --input-type yaml --output-type yaml "$tmp" > secrets/secrets.yaml
shred -u "$tmp"
```

`--filename-override` が要るのは、`.sops.yaml` の `creation_rules` が
`secrets/*.yaml` にしかマッチせず、tmpfile のパスでは受信者が決まらないため。

`git add secrets/secrets.yaml` してコミットする。中身が暗号化されているか確認:

```sh
grep -c 'BEGIN OPENSSH' secrets/secrets.yaml   # 0 なら OK
```

## clone 元 URL を指定して clone する

対象ユーザーのhomeモジュールの `local.profile` に各repoのURLとパスを足す。既存2台では `profiles/home/pomu-workstation.nix` に定義する（`agentConfigRoot` だけは `profiles/home/pomu-agents.nix` にあり、`pomu-workstation.nix` がそれを import する）。以下は `local.profile = { ... };` の内部に置く。
現在自動 clone に対応しているのは以下 4 種類の repo:

```nix
# Obsidian vault（ノート本文, private）
zettelkastenRoot    = "/home/pomu/sagyo/zettelkasten";
zettelkastenRepoUrl = "git@github.com:khimoo/zettelkasten.git";

# Claude Code のユーザー設定 (private)
agentConfigRoot = "/home/pomu/sagyo/agents-private";
agentConfigRepo = "git@github.com:khimoo/agents-private.git";

# Zettelkasten workflow repo (mirror-vault の宛先)
vaultSkeletonRepo    = "/home/pomu/sagyo/zettelkasten-workflow";
vaultSkeletonRepoUrl = "git@github.com:khimoo/zettelkasten-workflow.git";

# LLM Wiki 群 (private, clone するだけで他の配線は無い)
llmWikisRoot    = "/home/pomu/sagyo/llm-wikis";
llmWikisRepoUrl = "git@github.com:khimoo/llm-wikis.git";
```

switch した後に `clone-repos` を実行すると、dest が無い repo が clone される。`dev/claude.nix` の
symlink（Claude 側）、`services.zettelkasten` の同期（vault 側）、`mirror-vault`（workflow repo 側）は
switch で配線済みで、clone した時点から使える。デスクトップの papis の mount は、vault の `.git` が
現れた時点で path unit が始める（[disk-tiering.md](./disk-tiering.md)）。

vault は `services.zettelkasten.initializeVault` でも作れるが、この repo では使わない。
clone より先に空フォルダができると clone が失敗するため、vault の用意は clone 側に一本化する。

## 手元の checkout をまとめて更新する（`pull-repos`）

clone は初回だけで、switch は既存の working tree を触らない。更新は `pull-repos` で行う:

```sh
pull-repos
```

対象は自動 clone の対象 repo に flake 自身を加えたもの。この環境では
`flake_public` / `zettelkasten` / `agents-private` / `zettelkasten-workflow` / `llm-wikis`。
`local.profile.privateRepos` から組み立てるので、ユーザーの `local.profile.privateRepos` にrepoを足せば対象も増える。

各 repo で `git pull --ff-only` を走らせる。ローカルにコミットがあって分岐している repo は
git が拒否するので、そこだけ手で rebase / merge する。1 つ失敗しても残りは処理し、
最後に非ゼロで終わる。まだ clone されていない dest は報告のみで、clone は `clone-repos` で行う。

## SSH 鍵以外の秘密を配る

同じ `secrets/secrets.yaml` から、任意のパスへ秘密を書き出せる。

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops secrets/secrets.yaml
```

エディタで項目を足したら、配布先を宣言する。

```nix
local.profile.secrets = [
  {
    secret = "gemini_api_key";
    path = "${config.home.homeDirectory}/.config/gemini/api-key";
  }
];
```

`mode` は省略すると `600`。書き出し先が home の外だと評価時に弾かれる。
switch のたびに、宣言した通常のファイルを暗号文の内容と mode に揃える。手で置いた・書き換えたファイルも戻るので、秘密を変えるときは `secrets/secrets.yaml` を直す（[SSH 鍵を差し替えたとき](#ssh-鍵を差し替えたとき)）。宣言から外した秘密は、配置記録にある通常のファイルなら switch が消す。symlink やディレクトリは警告して触らない。

SSH 鍵は `local.profile.sshKeys = [{ secret, name }]` のままでよい。
`~/.ssh` へ `600` で置く場合は、そちらのほうが短く書ける。

## 新しい環境を足す

1. 専用 age 鍵を新環境の `~/.config/sops/age/keys.txt` に置く
   （既存マシンから SSH 送信、または Bitwarden から取得）
2. switch する（鍵が書き出される）
3. `clone-repos` を実行する

age 鍵 1 本を全環境で共有するため、マシンごとの受信者追加・再暗号化（`sops updatekeys`）は
不要。SSH 鍵の生成も登録も要らない。

## SSH 鍵を差し替えたとき

switch は既存の鍵も暗号文の内容に揃える。GitHub やほかのマシンは操作しない。
GitHub の鍵は次の順で差し替える。

1. 新しい鍵を作り、`secrets/secrets.yaml` の `git_ssh_key` を作り直して commit する。手順は
   [初回セットアップの 4.](#4-両方を暗号化してコミット) と同じで、差し替えたほうの鍵ファイルを新しいものにしてから
   両方まとめて再暗号化する。
2. GitHub に新しい公開鍵を登録する（`gh ssh-key add`）。登録前に switch すると、秘密鍵だけが新しくなり、
   その時点から GitHub に繋がらなくなる。
3. 各マシンで pull して switch し、`ssh -T git@github.com` で確かめる:
   ```sh
   git pull --ff-only
   sudo nixos-rebuild switch --flake .#<host>
   ssh -T git@github.com
   ```
4. 全マシンで確かめてから、GitHub の古い鍵を失効させる。失効させた後は、Nix の世代を戻しても
   古い鍵での認証は戻らない。

LAN 鍵は `lanPublicKey`（`authorized_keys`）も同時に変えるので、全機を回りきるまで一部の組み合わせで
SSH が通らない。手順は [machine-ssh.md の「LAN 共通鍵を作り直すとき」](./machine-ssh.md#lan-共通鍵を作り直すとき)。

## age 鍵を作り直す

age 鍵は `secrets.yaml` を開ける唯一の鍵なので、失えば暗号文は永久に読めない。ただし中身は
**復元可能な SSH 鍵 2 本だけ**なので、詰みはしない。どちらのケースでも
やることは「新しい age 鍵で `secrets.yaml` を作り直す」＝[初回セットアップ](#初回セットアップ)のやり直し。

**失った（Bitwarden にも無い、どのマシンにも残っていない）場合**

- SSH 秘密鍵がまだどれかのマシンの `~/.ssh/` に残っていれば、それを材料に
  初回セットアップ 1〜4 をやり直すだけでよい
- 残っていなければ、先に SSH 鍵を作り直して GitHub に登録し（初回セットアップ 3.）、
  LAN 側は `hosts/machines.nix` の `lanPublicKey` も差し替える

**漏らした場合は SSH 鍵も同時に作り直す。** git の履歴には過去の `secrets.yaml` が残っており、
漏れた age 鍵があればその全バージョンが復号できる。したがって「中に入っていた SSH 鍵は
既に漏れたもの」として扱い、GitHub 側の鍵を revoke して新しい鍵で暗号化し直す。
LAN 鍵も同様に作り直す。

作り直したあとは、各マシンの `~/.config/sops/age/keys.txt` を新しい鍵に置き換える
（古い鍵が残っていると、新しい暗号文を復号できず activation が失敗する）。

## 無効化する

本人の `local.profile` の URL 側（`zettelkastenRepoUrl` / `agentConfigRepo` / `vaultSkeletonRepoUrl`）を
消す（既定 `null`）とその repo は `clone-repos` の対象から外れる。dest 側（`zettelkastenRoot` /
`agentConfigRoot` / `vaultSkeletonRepo`）だけ残せば、同期や symlink、`mirror-vault` は
効くので、clone を手動運用に戻せる。

全clone URL・追加の `privateRepos` / `sshKeys` を外し、`lanSsh = false` にすれば、NixOSでもstandaloneでも鍵の書き出しは無くなりage鍵は不要になる。配置記録にある通常のファイルは、次の switch で削除される。追加の `secrets` も空であることが条件になる。
既存2台のpomuは `lanSsh = true` なので、自動cloneだけ外してもage鍵が必要。[fail-fastの設計判断](../architecture/private-repo-clone.md#fail-fastage-鍵が無ければ-switch-を失敗させる)も参照。

## 注意

- `secrets/secrets.yaml` は暗号文。**平文の秘密鍵・age 鍵を repo に置かないこと**
- 新しい環境の switch に **事前の SSH 鍵は不要**（clone は switch の後の `clone-repos` で行う）。`inputs.zettelkasten` を
  `github:`（public repo）で取得するようになり eval が SSH 鍵を要求しなくなったため、
  専用 age 鍵 1 本だけで switch でき、SSH 鍵は activation が `secrets.yaml` から書き出す
  （経緯は [architecture ドキュメント](../architecture/private-repo-clone.md#ゼロからの復元eval-時の鍵依存は解消済み)を参照）
