# Zotero PDF の Google Drive 同期（使い方・鍵運用）

Zotero のリンク添付 PDF (`~/Zotero-PDFs`) を、複数マシン間で Google Drive 経由で
双方向同期する。同期は rclone bisync、トリガーは watchexec のフォルダ監視。
秘密（rclone.conf）は sops-nix で暗号化管理する。

設計判断・セキュリティモデルは [../architecture/zotero-gdrive-sync.md](../architecture/zotero-gdrive-sync.md) を参照。

## 対応環境

- NixOS ホスト（`nixos-desktop`, `nixos-spin713`）: `features.zoteroSync = true` を設定済み
- macOS / その他 standalone home-manager: `mkHome` の `features.zoteroSync = true` で有効化

`features.zoteroSync` が偽の環境（WSL 等）では一切読み込まれず影響しない。

## 前提（Zotero 側の設定・全マシン共通）

PDF のバイトを `~/Zotero-PDFs` に**リンク添付**として置き、その相対パスを全マシンで
一致させるのが要点。rclone は `~/Zotero-PDFs` の中身だけを同期し、メタデータ/citekey は
Zotero 純正のデータ同期に任せる、という役割分担にする。以下は Zotero 7 の UI 名称
（バージョンで多少変わる）。

### 1. リンク添付ベースディレクトリを設定（最重要・相対パス化）

設定 → 詳細 → ファイルとフォルダ → **リンク添付ファイルのベースディレクトリ** を
`~/Zotero-PDFs` にする。これで各リンク添付が**このディレクトリからの相対パス**で保存され、
`~/Zotero-PDFs` の中身さえ同期すれば別マシンでも同じ相対パスで解決できる（マシンごとに
ホームディレクトリが違っても、ベースディレクトリを各機で `~/Zotero-PDFs` にすれば揃う）。

### 2. 取り込み PDF を `~/Zotero-PDFs` にリンク添付として置く

手動なら「ファイルへのリンク」で添付し、実体を `~/Zotero-PDFs` 以下に置く。自動化するなら
以下のどちらかのプラグインを導入し、移動先を `~/Zotero-PDFs` に設定する:

- **zotmoov**: 設定 → ZotMoov → 移動先ディレクトリ = `~/Zotero-PDFs`、
  「リンク添付として追加（add as linked attachment）」を有効化
- **attanger**: 添付の自動リネーム＋指定フォルダへの移動＋リンク化。移動先を
  `~/Zotero-PDFs` にする

いずれも「**リンク**添付（linked file）」であることが必須。**保存/インポート添付（stored）**
だと実体が Zotero の SQLite ストレージに入り、`~/Zotero-PDFs` に出てこない。

### 3. Zotero 純正のファイル同期を OFF（rclone と競合させない）

設定 → 同期 → ファイル同期 → 「マイライブラリの添付ファイルを同期」を **OFF**。
PDF のバイトは rclone、メタデータ/citekey は Zotero のデータ同期（オンのまま）が担当する。
両方を同期に掛けると二重管理・競合の原因になる。

## このリポジトリを初めて使うマシンのセットアップ

> **`sops` コマンドについて**: この環境では `sops` をグローバル導入していない。以下の
> `sops ...` は `nix shell nixpkgs#sops -c sops ...` の形で実行する
> （例: `nix shell nixpkgs#sops -c sops updatekeys secrets/rclone.yaml`）。
>
> **復号先パス（`$SECRET`）**: sops が復号した rclone.conf の場所。Linux は
> `~/.config/sops-nix/secrets/rclone_conf`、macOS は `config.sops.secrets."rclone_conf".path`
> （`nix eval` 等で確認）。素の `rclone` を叩くときはこれを `--config` に渡す
> （`zotero-sync` ラッパーは自動で使う）。本書のシェル例では `SECRET` 変数に入れて参照する。

### 1. ユーザ SSH 鍵を用意（復号鍵に流用する）

```sh
ls ~/.ssh/id_ed25519 || ssh-keygen -t ed25519
```

### 2. 公開鍵を age に変換して受信者に追加

```sh
nix shell nixpkgs#ssh-to-age -c sh -c 'ssh-to-age < ~/.ssh/id_ed25519.pub'
```

出力（`age1...`）を `.sops.yaml` の `keys:` に追加し、`creation_rules` の
`age:` グループにも参照（`*host_...`）を足す。

### 3. 既存の暗号化 secret に新しい受信者を反映

受信者に含まれる既存マシン（desktop 等）で:

```sh
export SOPS_AGE_SSH_PRIVATE_KEY_FILE=~/.ssh/id_ed25519
sops updatekeys secrets/rclone.yaml
```

これで新マシンの鍵でも復号できるよう再暗号化される。変更をコミット。

### 4. （最初の1台のみ）Google Drive remote と secret を作成

**最初の1台だけ**の作業。2台目以降は同じ `secrets/rclone.yaml` を共有するので、この手順は
不要（手順3で受信者に鍵を足すだけ）。既に `secrets/rclone.yaml` があるならスキップ。

#### 4-1. `rclone config` の対話（remote 名 = gdrive）

```sh
rclone config
```

各プロンプトへの回答（rclone のバージョンで番号は変わるので、**番号でなく文字列で回答**
するのが安全）:

| プロンプト | 回答 | 補足 |
|-----------|------|------|
| `n/s/q>` | `n` | New remote |
| `name>` | `gdrive` | `impl.nix` の `remoteName` と一致必須 |
| `Storage>` | `drive` | Google Drive |
| `client_id>` | （空 Enter） | rclone 内蔵アプリを使う。自前 OAuth アプリがあるなら設定 |
| `client_secret>` | （空 Enter） | 同上 |
| `scope>` | `drive.file` | **フルの `drive` にしない**。漏洩時の被害を rclone 作成ファイルに限定 |
| `service_account_file>` | （空 Enter） | 個人アカウントなので不要 |
| `Edit advanced config?` | `n` | |
| `Use auto config?` | `y`（ブラウザのある機）/ `n`（ヘッドレス、下記） | |
| （ブラウザ認証） | Google でログイン → 許可 | scope=drive.file の同意画面が出る |
| `Configure this as a Shared Drive (Team Drive)?` | `n` | 個人 Drive |
| `Keep this "gdrive" remote?` | `y` | |
| `e/n/d/r/c/s/q>` | `q` | quit |

**ヘッドレス機（SSH 先・ブラウザ無し）の場合**（`Use auto config? → n`）:
rclone が `rclone authorize "drive" "..."` の実行を促すので、**ブラウザのある別マシン**
（同じ rclone バージョン推奨）でそれを実行し、出力された token JSON を `config_token>` に
貼る。詳細: <https://rclone.org/remote_setup/>

#### 4-2. 生成された rclone.conf を暗号化 secret にする

`rclone config` は `~/.config/rclone/rclone.conf` に**平文**で書く。これを sops で暗号化して
リポジトリの `secrets/rclone.yaml` に取り込む:

```sh
# 既存 remote が gdrive だけか確認（他があるとまるごと入るので注意）
rclone listremotes

# rclone.conf を YAML ブロックスカラーとして埋め込み、その場で暗号化
# （暗号化は .sops.yaml の受信者=公開鍵だけで行うので、秘密鍵の export は不要）
mkdir -p secrets
{ echo "rclone_conf: |"; sed 's/^/  /' ~/.config/rclone/rclone.conf; } > secrets/rclone.yaml
nix shell nixpkgs#sops -c sops --encrypt --in-place secrets/rclone.yaml

# 平文が残っていないか（値が ENC[...] になっているか。2 以上なら暗号化済み）
grep -c 'ENC\[' secrets/rclone.yaml
git add secrets/rclone.yaml
```

暗号化後の `secrets/rclone.yaml` はこういう構造（`rclone_conf` の値が `ENC[...]`）:

```yaml
rclone_conf: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
sops:
    age:
        - recipient: age1...          # 受信マシンごとに1エントリ
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            ...
    ...
```

平文の中身（`sops secrets/rclone.yaml` でエディタを開くと見える）は、`rclone config` が
作った rclone.conf そのもの:

```
[gdrive]
type = drive
scope = drive.file
token = {"access_token":"...","refresh_token":"...","expiry":"..."}
```

> `.sops.yaml` の受信者に全マシンの鍵が入った状態で `sops updatekeys secrets/rclone.yaml`
> を実行してからコミットする。暗号化ファイルは公開リポジトリにコミットしてよい（平文は絶対に不可）。

### 5. rebuild / switch

```sh
# NixOS
sudo nixos-rebuild switch --flake .#nixos-desktop
# standalone（macOS 等）
home-manager switch --flake .#pomu-macos
```

> macOS を追加する場合は、事前に `mkHome` の `pomu-macos` に `features.zoteroSync = true`
> を足しておくこと（このマシンの鍵を受信者へ追加した後で）。

### 6. Zotero-PDFs ディレクトリと初回 baseline

ディレクトリは Zotero 側の設定で作られる（このモジュールは作らない）。以下の順序を守る:

```sh
SECRET=~/.config/sops-nix/secrets/rclone_conf   # 復号先（前述）

# a. Drive 側フォルダを一度だけ作る（無いと resync が directory not found で失敗する）
rclone --config "$SECRET" mkdir gdrive:Zotero-PDFs

# b. PDF が入った状態で baseline を作る（空ディレクトリで作ると以降の同期を拒否される）
zotero-sync --resync

# c. baseline が出来てから watcher を起動する
systemctl --user restart zotero-watch
```

> **順序が重要**（理由は設計ドキュメントの
> [運用上の性質・既知の制約](../architecture/zotero-gdrive-sync.md#運用上の性質既知の制約)
> を参照）:
> - **PDF を入れてから** resync する。空↔空だと以降の同期が `Empty prior Path1 listing`
>   で拒否される。空で作ってしまったら、PDF を入れて
>   `ZOTERO_FORCE_RESYNC=1 zotero-sync --resync` で作り直す。
> - **resync してから** watcher を起動する。baseline 無しで watcher が動くと、毎回の同期が
>   `must run --resync` で失敗し続ける。

## 動作確認（スモークテスト）

rebuild 直後、Zotero 設定前でも「復号 → rclone → Drive 到達」まで確認できる。以下の
`SECRET` は前述の復号先パス（macOS では値が異なる。セットアップ節冒頭の注記を参照）。

```sh
SECRET=~/.config/sops-nix/secrets/rclone_conf

# 1. sops が復号できているか（[gdrive]/type/scope が見える。token 行は出さない）
ls -l "$SECRET"                                    # mode 0400・所有者=自分
grep -e '^\[gdrive\]' -e '^type' -e '^scope' "$SECRET"

# 2. rclone がこの config を認識するか
rclone --config "$SECRET" listremotes              # → gdrive:

# 3. Drive への到達（OAuth 実地。exit 0 なら認証OK。drive.file なので中身は空でよい）
rclone --config "$SECRET" lsd gdrive:; echo "exit=$?"

# 4. watcher の状態（~/Zotero-PDFs 未作成なら「正常終了(0)で待機」が正しい姿）
systemctl --user status zotero-watch --no-pager | head
```

書き込み往復まで確かめたい場合（テスト後に消す）:

```sh
mkdir -p ~/Zotero-PDFs
rclone --config "$SECRET" mkdir gdrive:Zotero-PDFs         # 初回のみ
echo "test $(date)" > ~/Zotero-PDFs/__synctest__.txt
ZOTERO_FORCE_RESYNC=1 zotero-sync --resync                # 中身ありで baseline を作る
rclone --config "$SECRET" lsf gdrive:Zotero-PDFs          # → __synctest__.txt が見えれば UP OK

# 後始末（両側から直接消す。bisync 経由だと 100% 削除で --max-delete に掛かる）
rclone --config "$SECRET" delete gdrive:Zotero-PDFs/__synctest__.txt
rm -f ~/Zotero-PDFs/__synctest__.txt
rm -f ~/.cache/rclone/bisync/*                            # 本番前に baseline をクリア
```

> スモークテストで作る baseline は空/テスト用。本番 PDF を入れたら手順6で作り直すこと。

## 2台目以降を追加するとき（初回 --resync の順序が重要）

bisync の初回 `--resync` は baseline を確立する破壊的操作。**順序を守ること**:

1. **データを持つ側（例: desktop）** で先に `zotero-sync --resync`
   → Drive が desktop の内容のミラーになる
2. **新しい側（Zotero-PDFs が空）** で `zotero-sync --resync`
   → Drive から pull される

新マシンにローカル PDF が既にある状態で `--resync` すると衝突するので、
可能なら空の状態で 2 を実行する。

> 既に baseline がある状態で誤って `--resync` すると `zotero-sync` が中止する
> （上書き防止ガード）。本当にやり直す場合のみ `ZOTERO_FORCE_RESYNC=1 zotero-sync --resync`。

## 日常運用

- ローカルで PDF が増減すると watcher が検知し、5 秒デバウンス後に自動 bisync
- 他マシンで追加した PDF は、次に自分がローカル変更 / 手動同期 / ログインした時に pull される
  （リアルタイムではない）
- 手動同期: `zotero-sync`
- 削除は双方向に伝播するが、Drive 側はゴミ箱に送られる（30 日は復元可）。
  さらに `--max-delete`（既定 50%）ガードで大量削除は中断する
- 同期の実行ログ・エラーを見る:
  - Linux: `journalctl --user -u zotero-watch -f`
  - macOS: `~/Library/Logs/zotero-watch.log`（`launchd.agents` の出力先）

## トークンが失効/ローテートしたとき

sops の復号先 rclone.conf（前述の `$SECRET`、mode 0400）は
**読み取り専用**なので、rclone は refresh 後の access token を書き戻せず warning を出す。
ただし refresh token は長命なので継続動作する（warning は無視してよい）。

Google が refresh token 自体を失効させた（長期間未使用・パスワード変更・アプリ連携解除など）
場合のみ、手順 4-1 の `rclone config` で再認証し、手順 4-2 で再暗号化 → コミット → rebuild。

## デバイスを廃棄するとき

`.sops.yaml` からそのマシンの受信者（`&host_...` と `age:` の参照）を削除し、

```sh
sops updatekeys secrets/rclone.yaml
```

で再暗号化してコミット。以後その鍵では復号できなくなる。

## トラブルシューティング

| 症状 | 原因 / 対処 |
|------|-------------|
| `zotero-watch` が inactive で始まらない | `~/Zotero-PDFs` が未作成。Zotero 設定後 `systemctl --user restart zotero-watch` |
| bisync が `must run --resync` で失敗 | baseline 未作成。`zotero-sync --resync`（順序は上記） |
| resync が `directory not found` で失敗 | Drive 側 `Zotero-PDFs` フォルダが未作成。`rclone --config "$SECRET" mkdir gdrive:Zotero-PDFs`（`$SECRET`=前述の復号先）を一度だけ実行してから resync |
| `Empty prior Path1 listing ...` で失敗 | 空ディレクトリで baseline を作った。PDF を入れて `ZOTERO_FORCE_RESYNC=1 zotero-sync --resync` で作り直す |
| `--resync` が中止される | baseline が既存。誤操作防止ガード。意図的なら `ZOTERO_FORCE_RESYNC=1` |
| 新ホストで復号失敗 / secret が空 | `.sops.yaml` にそのホストの鍵を追加し `sops updatekeys` したか確認 |
| `.conflict` ファイルが出る | 2 台が同時更新した衝突。中身を確認して手動で正しい方を残す |
| token 書き戻し warning | 仕様（read-only）。refresh token が生きていれば無視してよい |
