# private repo の宣言的 clone（home-manager・age 鍵 1 本）

新しい環境に flake を適用したとき、private repo（Claude 設定など）を
**手で `git clone` せず**に自動 clone する運用。NixOS でも 非 NixOS（WSL / macOS）でも
同じ経路（home-manager の `home.activation`）で動く。

設計判断は [docs/architecture/private-repo-clone.md](../architecture/private-repo-clone.md) を参照。

## 仕組みの概要

- 各環境に置く秘密は **専用 age 鍵 1 本だけ**（`~/.config/sops/age/keys.txt`）。
  これを新環境へ渡す手段は 2 つ:
  - 既存マシンから SSH でファイルを送る
  - Bitwarden から取り出す
- GitHub 登録済みの**ユーザー SSH 鍵**（既存のものを流用）を **sops で暗号化して
  `secrets/secrets.yaml` にコミット**する。暗号文なので公開 repo でも安全。
- `home.activation` が switch のたびに:
  1. age 鍵があれば `secrets.yaml` を復号し、`~/.ssh/id_ed25519` が無ければ書き出す
  2. `claudeConfigRoot` が無ければ、その SSH 鍵で `claudeConfigRepo` を clone する
  既にあるものは触らない（上書き・pull はしない＝非破壊）。

`claudeConfigRepo`（clone 元 URL）を指定しない限り、activation は一切生えない。
公開 flake をそのまま使う人・自前 repo を手動 clone したい人には無影響。

## 有効化する（初回セットアップ、1 回だけ）

### 1. 専用 age 鍵を作る

```sh
nix-shell -p age --run 'age-keygen -o keys.txt'
```

- 出力の `# public key: age1...` を控える（次の手順で `.sops.yaml` に入れる）
- `keys.txt`（`AGE-SECRET-KEY-...` を含む）は **Bitwarden に保管**し、
  各環境の `~/.config/sops/age/keys.txt` に置く。**公開 repo にはコミットしない**

### 2. `.sops.yaml` の recipient を実鍵に差し替える

リポジトリ直下の [.sops.yaml](../../.sops.yaml) のプレースホルダ
（`age1REPLACE_DEDICATED_AGE_PUBLIC_KEY`）を 1. の公開鍵に置き換える。

### 3. ユーザー SSH 鍵を暗号化してコミット

age 鍵を sops に使わせてから、既存のユーザー鍵を `git_ssh_key` として暗号化する:

```sh
mkdir -p secrets
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
nix-shell -p sops --run 'sops secrets/secrets.yaml'
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

### 4. `claudeConfigRepo` を指定して switch

対象環境の `flake.nix` 呼び出しに clone 元 URL を足す（clone 先 `claudeConfigRoot` は既存）:

```nix
claudeConfigRoot = "/home/pomu/sagyo/claude-private";
claudeConfigRepo = "git@github.com:khimoo/claude-private.git";
```

switch すると、`claudeConfigRoot` が無い環境では clone され、その後 `dev/claude.nix` の
symlink が張られる。

## 新しい環境を足す

1. 専用 age 鍵を新環境の `~/.config/sops/age/keys.txt` に置く
   （既存マシンから SSH 送信、または Bitwarden から取得）
2. switch する

age 鍵 1 本を全環境で共有するため、マシンごとの受信者追加・再暗号化（`sops updatekeys`）は
不要。

## 無効化する

`flake.nix` の `claudeConfigRepo` を消す（既定 `null`）と自動 clone は止まる。
`claudeConfigRoot` だけ残せば symlink は効くので、clone を手動運用に戻せる。

## 注意

- `secrets/secrets.yaml` は暗号文。**平文の秘密鍵・age 鍵を repo に置かないこと**
- 新しい環境の switch に **事前の `~/.ssh/id_ed25519` は不要**。`inputs.zettelkasten` を
  `github:`（public repo）で取得するようになり eval が SSH 鍵を要求しなくなったため、
  専用 age 鍵 1 本だけで switch でき、SSH 鍵は activation が `secrets.yaml` から書き出す
  （経緯は [architecture ドキュメント](../architecture/private-repo-clone.md#ゼロからの復元eval-時の鍵依存は解消済み)を参照）
