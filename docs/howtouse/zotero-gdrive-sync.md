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

1. `zotmoov`（または `attanger`）プラグインを導入
2. リンク添付のベースディレクトリを `~/Zotero-PDFs` に設定し、取り込み PDF をそこへ移動
3. 設定 → 同期 → ファイル同期の「添付ファイルを同期」を **OFF**
   （メタデータ/citekey は Zotero 純正のデータ同期が担当。rclone は PDF のバイトだけ扱う）

## このリポジトリを初めて使うマシンのセットアップ

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

まだ `secrets/rclone.yaml` が存在しない場合のみ。

```sh
# OAuth。scope は drive.file を選ぶ（漏洩時の被害を rclone 作成ファイルに限定）
rclone config      # name=gdrive, storage=drive, scope=drive.file

# 暗号化ファイルを作成（保存で自動暗号化。SSH 鍵を編集 identity に使う）
export SOPS_AGE_SSH_PRIVATE_KEY_FILE=~/.ssh/id_ed25519
sops secrets/rclone.yaml
```

`secrets/rclone.yaml` の中身（`rclone config` が作った `[gdrive]` ブロックを貼る）:

```yaml
rclone_conf: |
  [gdrive]
  type = drive
  scope = drive.file
  token = {"access_token":"...","refresh_token":"...","expiry":"..."}
  team_drive =
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

ディレクトリは Zotero 側の設定で作られる（このモジュールは作らない）。存在後:

```sh
systemctl --user restart zotero-watch   # dir 待ちで停止していた watcher を起動（Linux）
zotero-sync --resync                    # 初回 baseline を作成
```

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

## トークンが失効/ローテートしたとき

`/nix/store` 経由の rclone.conf は読み取り専用なので、rclone は refresh 後の
access token を書き戻せず warning を出すが、refresh token は長命なので継続動作する。
Google が refresh token を失効させたら手順 4 の `rclone config` → `sops secrets/rclone.yaml`
を再実行して再暗号化・コミット・rebuild。

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
| `--resync` が中止される | baseline が既存。誤操作防止ガード。意図的なら `ZOTERO_FORCE_RESYNC=1` |
| 新ホストで復号失敗 / secret が空 | `.sops.yaml` にそのホストの鍵を追加し `sops updatekeys` したか確認 |
| `.conflict` ファイルが出る | 2 台が同時更新した衝突。中身を確認して手動で正しい方を残す |
| token 書き戻し warning | 仕様（read-only）。refresh token が生きていれば無視してよい |
