# papis ライブラリの Google Drive 同期（使い方・鍵運用）

papis ライブラリ (`~/papis-library`) を、複数マシン間で Google Drive 経由で
双方向同期する。同期は rclone bisync、トリガーは watchexec のフォルダ監視。
秘密（rclone.conf）は sops-nix で暗号化管理する。

papis は item ごとに `info.yaml`（平文メタデータ）と PDF 実体を同じフォルダに置くので、
`~/papis-library` を丸ごと 1 本の bisync で同期すればメタデータも PDF も同時に揃う
（Zotero 時代の「メタデータ=純正同期 / PDF=rclone」の 2 系統が 1 系統に減る）。

設計判断・セキュリティモデルは [../architecture/papis-gdrive-sync.md](../architecture/papis-gdrive-sync.md) を参照。

## 対応環境

- NixOS ホスト（`nixos-desktop`, `nixos-spin713`）: `features.referenceSync = true` を設定済み
- macOS / その他 standalone home-manager: `mkHome` の `features.referenceSync = true` で有効化

`features.referenceSync` が偽の環境（WSL 等）では一切読み込まれず影響しない。

papis 本体は `modules/home-manager/papis/app.nix` が `gui` 有効な環境に導入する
（`referenceSync` とは独立）。本書は papis が入っている前提で、そのライブラリ同期の
セットアップを扱う。

## papis の基本ワークフロー（全マシン共通）

Zotero と違いリンク添付や純正ファイル同期の設定は不要。papis は追加した item を
`~/papis-library/<item>/` フォルダにまとめ、その中に `info.yaml`（メタデータ）と
PDF 実体を同居させる。このフォルダごと rclone bisync するだけで両方が揃う。

### 1. 文献を追加する

```sh
# PDF から（DOI などが埋まっていれば自動でメタデータ取得）
papis add --set ref hottbook path/to/paper.pdf

# DOI 指定で追加
papis add --from doi 10.1000/xyz123
```

`~/papis-library/<item>/{info.yaml, *.pdf}` が作られる。この瞬間から watcher が検知して
自動同期する（初回 baseline を作成済みの場合。未作成なら[初回 baseline](#6-papis-library-と初回-baseline) 参照）。

### 2. citekey を pin する（`ref:`）

引用はファイルパスでなく citekey で参照するので、各 item の `info.yaml` の `ref:` に
安定した citekey を手で pin する運用にしている（自動 `ref-format` はあえて設定していない。
理由は[設計ドキュメント](../architecture/papis-gdrive-sync.md)参照）。

```yaml
# ~/papis-library/<item>/info.yaml
ref: hottbook
author: ...
title: ...
```

`papis edit` でエディタを開いて `ref:` を設定してもよい。

### 3. 原稿から引用する

`.bib` を書き出して LaTeX/Markdown から `[@citekey]` や `\cite{citekey}` で参照する:

```sh
# ライブラリ全体を BibTeX で書き出し（手動運用。自動書き出しはしていない）
papis export --all --format bibtex > references.bib
```

## このリポジトリを初めて使うマシンのセットアップ

> **`sops` コマンドについて**: この環境では `sops` をグローバル導入していない。以下の
> `sops ...` は `nix shell nixpkgs#sops -c sops ...` の形で実行する
> （例: `nix shell nixpkgs#sops -c sops updatekeys secrets/rclone.yaml`）。
>
> **復号先パス（`$SECRET`）**: sops が復号した rclone.conf の場所。Linux は
> `~/.config/sops-nix/secrets/rclone_conf`、macOS は `config.sops.secrets."rclone_conf".path`
> （`nix eval` 等で確認）。素の `rclone` を叩くときはこれを `--config` に渡す
> （`papis-sync` ラッパーは自動で使う）。本書のシェル例では `SECRET` 変数に入れて参照する。

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
| `name>` | `gdrive` | `sync.nix` の `remoteName` と一致必須 |
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

> macOS を追加する場合は、事前に `mkHome` の `pomu-macos` に `features.referenceSync = true`
> を足しておくこと（このマシンの鍵を受信者へ追加した後で）。

### 6. papis-library と初回 baseline

`~/papis-library` は `papis add` が初めて item を追加したときに作られる
（このモジュールは作らない）。以下の順序を守る:

```sh
SECRET=~/.config/sops-nix/secrets/rclone_conf   # 復号先（前述）

# a. Drive 側フォルダを一度だけ作る（無いと resync が directory not found で失敗する）
rclone --config "$SECRET" mkdir gdrive:papis-library

# b. item が入った状態で baseline を作る（空ディレクトリで作ると以降の同期を拒否される）
papis-sync --resync

# c. baseline が出来てから watcher を起動する
systemctl --user restart papis-watch
```

> **順序が重要**（理由は設計ドキュメントの
> [運用上の性質・既知の制約](../architecture/papis-gdrive-sync.md#運用上の性質既知の制約)
> を参照）:
> - **item を入れてから** resync する。空↔空だと以降の同期が `Empty prior Path1 listing`
>   で拒否される。空で作ってしまったら、`papis add` で item を入れて
>   `PAPIS_FORCE_RESYNC=1 papis-sync --resync` で作り直す。
> - **resync してから** watcher を起動する。baseline 無しで watcher が動くと、毎回の同期が
>   `must run --resync` で失敗し続ける。

## 動作確認（スモークテスト）

rebuild 直後、papis に item を入れる前でも「復号 → rclone → Drive 到達」まで確認できる。以下の
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

# 4. watcher の状態（~/papis-library 未作成なら「正常終了(0)で待機」が正しい姿）
systemctl --user status papis-watch --no-pager | head
```

書き込み往復まで確かめたい場合（テスト後に消す）:

```sh
mkdir -p ~/papis-library
rclone --config "$SECRET" mkdir gdrive:papis-library      # 初回のみ
echo "test $(date)" > ~/papis-library/__synctest__.txt
PAPIS_FORCE_RESYNC=1 papis-sync --resync                  # 中身ありで baseline を作る
rclone --config "$SECRET" lsf gdrive:papis-library        # → __synctest__.txt が見えれば UP OK

# 後始末（両側から直接消す。bisync 経由だと 100% 削除で --max-delete に掛かる）
rclone --config "$SECRET" delete gdrive:papis-library/__synctest__.txt
rm -f ~/papis-library/__synctest__.txt
rm -f ~/.cache/rclone/bisync/*                            # 本番前に baseline をクリア
```

> スモークテストで作る baseline は空/テスト用。本番の item を入れたら手順6で作り直すこと。

## 2台目以降を追加するとき（初回 --resync の順序が重要）

bisync の初回 `--resync` は baseline を確立する破壊的操作。**順序を守ること**:

1. **データを持つ側（例: desktop）** で先に `papis-sync --resync`
   → Drive が desktop の内容のミラーになる
2. **新しい側（papis-library が空）** で `papis-sync --resync`
   → Drive から pull される

新マシンにローカル item が既にある状態で `--resync` すると衝突するので、
可能なら空の状態で 2 を実行する。

> 既に baseline がある状態で誤って `--resync` すると `papis-sync` が中止する
> （上書き防止ガード）。本当にやり直す場合のみ `PAPIS_FORCE_RESYNC=1 papis-sync --resync`。

## 日常運用

- ローカルで item が増減すると watcher が検知し、5 秒デバウンス後に自動 bisync
- 他マシンで追加した item は、次に自分がローカル変更 / 手動同期 / ログインした時に pull される
  （リアルタイムではない）
- 手動同期: `papis-sync`
- 削除は双方向に伝播するが、Drive 側はゴミ箱に送られる（30 日は復元可）。
  さらに `--max-delete`（既定 50%）ガードで大量削除は中断する
- 同期の実行ログ・エラーを見る:
  - Linux: `journalctl --user -u papis-watch -f`
  - macOS: `~/Library/Logs/papis-watch.log`（`launchd.agents` の出力先）

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
| `papis-watch` が inactive で始まらない | `~/papis-library` が未作成。`papis add` で item を追加後 `systemctl --user restart papis-watch` |
| bisync が `must run --resync` で失敗 | baseline 未作成。`papis-sync --resync`（順序は上記） |
| resync が `directory not found` で失敗 | Drive 側 `papis-library` フォルダが未作成。`rclone --config "$SECRET" mkdir gdrive:papis-library`（`$SECRET`=前述の復号先）を一度だけ実行してから resync |
| `Empty prior Path1 listing ...` で失敗 | 空ディレクトリで baseline を作った。`papis add` で item を入れて `PAPIS_FORCE_RESYNC=1 papis-sync --resync` で作り直す |
| `--resync` が中止される | baseline が既存。誤操作防止ガード。意図的なら `PAPIS_FORCE_RESYNC=1` |
| 新ホストで復号失敗 / secret が空 | `.sops.yaml` にそのホストの鍵を追加し `sops updatekeys` したか確認 |
| `.conflict` ファイルが出る | 2 台が同時更新した衝突。中身を確認して手動で正しい方を残す |
| token 書き戻し warning | 仕様（read-only）。refresh token が生きていれば無視してよい |
