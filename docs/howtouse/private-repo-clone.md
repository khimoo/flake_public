# private repo の宣言的 clone（home-manager・age 鍵 1 本）

新しい環境に flake を適用したとき、private repo（ノート本文・Claude 設定・Obsidian
workflow）を**手で `git clone` せず**に自動 clone する運用。NixOS でも 非 NixOS
（WSL / macOS）でも同じ経路（home-manager の `home.activation`）で動く。

設計判断は [docs/architecture/private-repo-clone.md](../architecture/private-repo-clone.md) を参照。

## 仕組みの概要

- 各環境に置く秘密は **専用 age 鍵 1 本だけ**（`~/.config/sops/age/keys.txt`）。
  これを新環境へ渡す手段は 2 つ:
  - 既存マシンから SSH でファイルを送る
  - Bitwarden から取り出す
- GitHub 登録済みの**ユーザー SSH 鍵**を **sops で暗号化して `secrets/secrets.yaml` に
  コミット**する。暗号文なので公開 repo でも安全。
- `home.activation` が switch のたびに:
  1. age 鍵があれば `secrets.yaml` を復号し、`~/.ssh/id_ed25519` が無ければ書き出す
  2. `settings.privateRepos` の各 `{ url, dest }` について、`dest` が無ければ SSH 鍵で clone する
  既にあるものは触らない（上書き・pull はしない＝非破壊）。

`settings.privateRepos` は `flake.nix` の `buildPrivateRepos` が高レベル設定
（`claudeConfigRepo` / `obsidianConfigRepoUrl` など、URL 側の設定）から組み立てる。
URL 側が `null` の項目は落とされるので、dest 側だけ指定すればその repo は手動 clone 運用に
留まる。**全 URL が未指定なら activation 自体が生えない**——つまりその環境では age 鍵も
`secrets.yaml` も無くて switch できる。

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

### 3. ユーザー SSH 鍵を暗号化してコミット

GitHub に登録済みの SSH 秘密鍵を `git_ssh_key` として暗号化する:

```sh
mkdir -p secrets
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
nix shell nixpkgs#sops -c sops secrets/secrets.yaml
```

エディタが開くので次のキーで秘密鍵の中身を貼る:

```yaml
git_ssh_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...（~/.ssh/id_ed25519 の中身）...
  -----END OPENSSH PRIVATE KEY-----
```

保存すると `secrets/secrets.yaml` が暗号化された状態で書かれる。
`git add secrets/secrets.yaml` してコミットする。

手元の鍵ファイルから直接暗号化するなら、下の
[SSH 鍵を差し替えたとき](#ssh-鍵を差し替えたとき)のコマンドが使える（エディタを開かず、
平文を端末に出さない）。

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
不要。

## SSH 鍵を差し替えたとき

GitHub 側の鍵を作り直したら、`secrets/secrets.yaml` も作り直す。エディタを開かずに
既存鍵から直接暗号化する（平文を端末に出さない）:

```sh
tmp=$(mktemp -p "$XDG_RUNTIME_DIR"); chmod 600 "$tmp"
{ echo 'git_ssh_key: |'; sed 's/^/  /' ~/.ssh/id_ed25519; } > "$tmp"
nix shell nixpkgs#sops -c sops --encrypt --filename-override secrets/secrets.yaml \
  --input-type yaml --output-type yaml "$tmp" > secrets/secrets.yaml
shred -u "$tmp"
```

activation は **`~/.ssh/id_ed25519` が既にあれば書き出さない**（非破壊）。つまり他の既存
マシンには旧鍵が残ったままなので、そちらは手で置き換える（消せば次の switch が新しい
暗号文から書き出す）。

## age 鍵を作り直す

age 鍵は `secrets.yaml` を開ける唯一の鍵なので、失えば暗号文は永久に読めない。ただし中身は
**GitHub の SSH 鍵という復元可能なもの 1 つだけ**なので、詰みはしない。どちらのケースでも
やることは「新しい age 鍵で `secrets.yaml` を作り直す」＝[初回セットアップ](#初回セットアップ)のやり直し。

**失った（Bitwarden にも無い、どのマシンにも残っていない）場合**

- SSH 秘密鍵がまだどれかのマシンの `~/.ssh/id_ed25519` に残っていれば、それを材料に
  初回セットアップ 1〜3 をやり直すだけでよい
- SSH 鍵も残っていなければ、先に
  [SSH 鍵を作り直して GitHub に登録](#ssh-鍵を差し替えたとき)してから 1〜3 をやる

**漏らした場合は SSH 鍵も同時に作り直す。** git の履歴には過去の `secrets.yaml` が残っており、
漏れた age 鍵があればその全バージョンが復号できる。したがって「中に入っていた SSH 鍵は
既に漏れたもの」として扱い、GitHub 側の鍵を revoke して新しい鍵で暗号化し直す。
age 鍵の差し替えだけでは不十分。

作り直したあとは、各マシンの `~/.config/sops/age/keys.txt` を新しい鍵に置き換える
（古い鍵が残っていると、新しい暗号文を復号できず activation が失敗する）。

## 無効化する

`flake.nix` の URL 側（`zettelkastenRepoUrl` / `claudeConfigRepo` / `obsidianConfigRepoUrl`）を
消す（既定 `null`）とその repo の自動 clone は止まる。dest 側（`zettelkastenRoot` /
`claudeConfigRoot` / `obsidianConfigRepo`）だけ残せば、同期や symlink、`mirror-obsidian` は
効くので、clone を手動運用に戻せる。
全 URL を消せば activation 自体が生えない。

## 注意

- `secrets/secrets.yaml` は暗号文。**平文の秘密鍵・age 鍵を repo に置かないこと**
- 新しい環境の switch に **事前の `~/.ssh/id_ed25519` は不要**。`inputs.zettelkasten` を
  `github:`（public repo）で取得するようになり eval が SSH 鍵を要求しなくなったため、
  専用 age 鍵 1 本だけで switch でき、SSH 鍵は activation が `secrets.yaml` から書き出す
  （経緯は [architecture ドキュメント](../architecture/private-repo-clone.md#ゼロからの復元eval-時の鍵依存は解消済み)を参照）
