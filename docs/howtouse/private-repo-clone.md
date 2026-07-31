# SSH 鍵の配布と private repo の宣言的 clone（home-manager・age 鍵 1 本）

新しい環境に flake を適用したとき、**手作業を age 鍵 1 本の設置だけ**にする運用。
SSH 鍵（GitHub 認証用と LAN 用）は switch が書き出し、private repo（ノート本文・
Claude 設定・Obsidian workflow）も switch が clone する。NixOS でも 非 NixOS
（WSL / macOS）でも同じ経路（home-manager の `home.activation`）で動く。

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

- `home.activation` が switch のたびに:
  1. `secrets.yaml` を age 鍵で復号し、まだ無い鍵ファイルだけ書き出す
  2. `settings.privateRepos` の各 `{ url, dest }` について、`dest` が無ければ
     `id_github` で clone する

  既にあるものは触らない（上書き・pull はしない＝非破壊）。
  **age 鍵が無い / 復号に失敗した場合は警告ではなく error で停止する**（switch が失敗する）。
  「switch は成功したのに鍵が無い」状態を作らないため。

どの鍵を配るかは環境の種類で決まる。NixOS ホストは `id_lan` も要るので両方、
standalone（WSL / macOS）は clone 対象がある場合に `id_github` だけ。

`settings.privateRepos` は `flake.nix` の `buildPrivateRepos` が高レベル設定
（`claudeConfigRepo` / `obsidianConfigRepoUrl` など、URL 側の設定）から組み立てる。
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

## clone 元 URL を指定して switch

対象環境の `flake.nix` 呼び出しに、各 repo の clone 元 URL を足す（clone 先の絶対パス側は既存）。
現在自動 clone に対応しているのは以下 3 種類の repo:

```nix
# Obsidian vault（ノート本文, private）
zettelkastenRoot    = "/home/pomu/sagyo/zettelkasten";
zettelkastenRepoUrl = "git@github.com:khimoo/zettelkasten.git";

# Claude Code のユーザー設定 (private)
claudeConfigRoot = "/home/pomu/sagyo/claude-private";
claudeConfigRepo = "git@github.com:khimoo/claude-private.git";

# Obsidian workflow repo (mirror-obsidian の宛先)
obsidianConfigRepo    = "/home/pomu/sagyo/zettelkasten-workflow";
obsidianConfigRepoUrl = "git@github.com:khimoo/zettelkasten-workflow.git";
```

switch すると、それぞれ dest が無い環境で clone される。その後 `dev/claude.nix` の
symlink（Claude 側）、`services.zettelkasten` の `.obsidian` 配置と同期（vault 側）、
`mirror-obsidian`（Obsidian config 側）がそれぞれ配線される。

vault は `services.zettelkasten.initializeVault` でも作れるが、この repo では使わない。
clone より先に空フォルダができると clone が失敗するため、vault の用意は clone 側に一本化する。

## 新しい環境を足す

1. 専用 age 鍵を新環境の `~/.config/sops/age/keys.txt` に置く
   （既存マシンから SSH 送信、または Bitwarden から取得）
2. switch する

age 鍵 1 本を全環境で共有するため、マシンごとの受信者追加・再暗号化（`sops updatekeys`）は
不要。SSH 鍵の生成も登録も要らない。

## SSH 鍵を差し替えたとき

GitHub 側の鍵を作り直した（または LAN 共通鍵を rotate した）ら、`secrets/secrets.yaml` も
作り直す。手順は[初回セットアップの 4.](#4-両方を暗号化してコミット) と同じ——差し替えた
ほうの鍵ファイルを新しいものにしてから、同じコマンドで両方まとめて再暗号化する。

activation は **既にあるファイルを書き出さない**（非破壊）。つまり他の既存マシンには旧鍵が
残ったままなので、そちらは手で消してから switch する:

```sh
rm ~/.ssh/id_github          # 差し替えたほうだけ
sudo nixos-rebuild switch --flake .#<host>
```

LAN 鍵を差し替えるときは全機を回りきるまで一部の組み合わせで SSH が通らない。
手順の詳細は [machine-ssh.md の「LAN 共通鍵を作り直すとき」](./machine-ssh.md#lan-共通鍵を作り直すとき)。

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

`flake.nix` の URL 側（`zettelkastenRepoUrl` / `claudeConfigRepo` / `obsidianConfigRepoUrl`）を
消す（既定 `null`）とその repo の自動 clone は止まる。dest 側（`zettelkastenRoot` /
`claudeConfigRoot` / `obsidianConfigRepo`）だけ残せば、同期や symlink、`mirror-obsidian` は
効くので、clone を手動運用に戻せる。

standalone 環境で全 URL を消せば SSH 鍵の書き出しごと生えなくなり、age 鍵も
`secrets.yaml` も無しで switch できる。NixOS ホストは `id_lan` が要るので鍵の書き出しは残る
——つまり **NixOS ホストは age 鍵が無いと switch できない**（[fail-fast の設計判断](../architecture/private-repo-clone.md#fail-fastage-鍵が無ければ-switch-を失敗させる)）。

## 注意

- `secrets/secrets.yaml` は暗号文。**平文の秘密鍵・age 鍵を repo に置かないこと**
- 新しい環境の switch に **事前の SSH 鍵は不要**。`inputs.zettelkasten` を
  `github:`（public repo）で取得するようになり eval が SSH 鍵を要求しなくなったため、
  専用 age 鍵 1 本だけで switch でき、SSH 鍵は activation が `secrets.yaml` から書き出す
  （経緯は [architecture ドキュメント](../architecture/private-repo-clone.md#ゼロからの復元eval-時の鍵依存は解消済み)を参照）
