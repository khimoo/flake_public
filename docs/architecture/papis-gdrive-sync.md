# papis ライブラリの Google Drive 同期（設計判断）

設定ファイル:
- vault flake `git+ssh://git@github.com/khimoo/zettelkasten` … papis の**仕組み**と vault 専用 secret を所有（どのマシン
  でも同一のワークフローを再現できる完結型モジュール）:
  - `nix/hm-module.nix`（統合モジュール `services.zettelkasten`。options を宣言し `nix/papis.nix` を import）
  - `nix/papis.nix`（papis 本体＋`programs.papis` 設定と同期 watcher を `papis.enable` で導入）
  - `nix/papis-sync-script.nix` / `nix/bisync-lib.nix`（同期スクリプト本体。env 駆動で secret も保存先も知らない）
  - `nix/with-rclone-secret.nix`（実行時復号ラッパー。同期の直前に `secrets/rclone.yaml` を復号し
    `RCLONE_CONFIG` として同期本体へ渡す。全環境の唯一の入口）
  - `.sops.yaml` / `secrets/rclone.yaml`（暗号化された rclone.conf。vault 専用 secret なので vault が持つ）
- flake_public 側（環境固有の配線だけ）:
  - `modules/home-manager/zettelkasten.nix`（唯一の glue。vault 本体を import し clone 位置 `zettelkastenRoot` と
    feature toggle を注入するだけ。secret の配線は不要＝同期スクリプト自身が実行時に復号する）

使い方・鍵運用の手順は [../howtouse/papis-gdrive-sync.md](../howtouse/papis-gdrive-sync.md) を参照。

## 全体構成

```
papis add ──> ~/sagyo/zettelkasten/references/<item>/{info.yaml, *.pdf} ──(watchexec)──> papis-sync
                                                                                          │
                                            rclone bisync (RCLONE_CONFIG=復号済み rclone.conf)
                                                                                          │
                                                                    Google Drive:papis-library
```

ライブラリ本体は vault 内 `references/`（Obsidian vault で完結）。nixos-desktop では
このパスに SATA subvol を被せ、実体をコールド層に置く（[disk-tiering.md](./disk-tiering.md)）。

同期対象は `nixos-desktop` / `nixos-spin713`、および将来の macOS（会社 PC）。
全マシンで同期スクリプト自身が **実行時に sops 復号**する統一構成（home-manager の有無に依らない）。

## 設計判断

### 参照文献マネージャは papis（平文）、Zotero 不採用

item ごとに **`info.yaml`（平文メタデータ）と PDF 実体が同じフォルダに同居**する。
これにより同期が 1 系統で済む（下記「同期対象は 1 フォルダ」）。設定は
`programs.papis`（home-manager）で `~/.config/papis/config` まで宣言生成でき、Nix で
参照文献まわりを完全に閉じられる。citekey はプラグイン（Zotero の Better BibTeX 等）に
依存せず、各 `info.yaml` の `ref:` に平文で pin する。

対して Zotero は citekey 生成に Better BibTeX プラグインが要り、そのプラグインを
宣言的にクリーンに導入できない（Zotero がプロファイルの `extensions.json` で管理し
activation-script と相性が悪い。BBT 8.0.26+ は Zotero 7 サポートを打ち切っており
nixpkgs の zotero とのバージョン固定の罠もある）。ここが移行の主動機。

### 同期対象は 1 フォルダ（メタデータとバイトを一本化）

papis はメタデータ（`info.yaml`）と PDF バイトを同じ item フォルダに置くので、
`references/`（`libraryDir`）を丸ごと 1 本の rclone bisync で同期すれば両方カバーできる。

Zotero では生きた SQLite を安全に rclone できず、metadata=Zotero 純正同期 +
PDF バイト=rclone の **2 系統**を強いられていた。papis 化でこの 2 系統が 1 系統に減る。

### 同期先は Google Drive（rclone）、Syncthing 不採用

既存インフラ（Google アカウント）に載せられ、片方がオフラインでもクラウド経由で
最終的に整合する。P2P 常時接続を前提にしない。

### 双方向は rclone bisync、timer ポーリング不採用

`sync`（一方向）でなく `bisync`。timer による定期 pull はレイテンシと無駄実行が多い。
トリガーはイベント駆動にする。

### トリガーは watchexec、systemd.path 不採用

`systemd.path` はディレクトリを **再帰監視できない**。papis ライブラリは item ごとの
サブフォルダ構造を持つため、再帰監視できる watchexec を常駐サービスにする。watchexec は
Linux/macOS 両対応なので、監視コマンド自体はプラットフォーム共通で、サービスの
包み（systemd.user / launchd.agents）だけを分岐する。

### 復号は実行時（同期スクリプト内）。activation 時でもシステム層でもない

変遷: 「NixOS システム側で `/run/secrets` に復号」→「home-manager sops-nix
（activation 時に復号先パスへ常駐）」→ 現在の「同期スクリプト自身が実行のたびに復号」。

- **レイヤリング**: rclone/Google Drive のトークンは *ユーザの関心事*。システム層が
  ユーザの Drive トークンを知る必要はない（ユーザ層で扱う判断は不変）
- **機構の一本化**: sops-nix は activation を要するため home-manager が無い環境で使えず、
  「HM 環境=sops-nix / 素の環境=手動復号」の 2 経路が生じていた。復号を実行時に移した
  ことで、NixOS・standalone home-manager・素の環境（`nix run`）が同一の入口
  （with-rclone-secret）を通り、環境差が構造的に消える
- **配線の消滅**: sops-nix 本体の import・復号鍵の指定（`sops.age.sshKeyPaths`）・
  `after=wants=sops-nix.service` の起動順序が全て不要になり、flake_public の glue は
  clone 位置と toggle だけになった
- **平文の常駐が消える**: 復号先に平文を置きっぱなしにせず、同期中だけ tmpfs に存在し
  終了時に削除される

トレードオフ: 復号の失敗が activation 時でなく実行時に判明する。これは既存の層3
preflight 思想（宣言的に用意できない要素は復旧手順つきで loud に落とす）に載せて吸収する。
毎同期の `sops -d` は数十 ms で、5 秒デバウンスの前では誤差。各マシンにユーザ復号鍵が
要る点は従来どおりで、下記のとおり既存の user SSH 鍵を流用するので新しい鍵は配らない。

### 復号鍵は各マシンの user SSH 鍵（ssh-to-age）

with-rclone-secret は既定で `~/.ssh/id_ed25519` を ssh-to-age で age 鍵に変換して復号する。
git/リモートビルドで各マシンに既にある ed25519 ユーザ鍵を流用し、新しい鍵の配布を避ける。
マシン単位の鍵なので、廃棄時はそのマシンの受信者を外して `sops updatekeys` すれば失効できる。
SSH 鍵を置けない環境（借り物 PC 等）では `SOPS_AGE_KEY(_FILE)` で持ち込みの age 鍵を渡せる
（受信者登録した専用鍵を Bitwarden 等に保管しておく運用）。

### papis の仕組みは vault flake が所有（flake_public は配線だけ）

papis 本体＋設定と同期は、vault リポジトリ（private repo `khimoo/zettelkasten`）の統合モジュール
`services.zettelkasten` が所有する。目的は **vault の完結性**: home-manager の有無に依らず、
この flake を使えばどのマシンでも同じ papis ワークフロー（本体・設定・Drive 同期）を再現できる。
`flake_public` はそれを input に取り込み、`modules/home-manager/zettelkasten.nix` で vault clone 位置と
feature toggle を注入するだけ（提供側=vault flake / 配線側=flake_public の依存性逆転）。

vault flake 内では papis を `nix/papis.nix` に分離し、統合モジュール本体（`nix/hm-module.nix`）が
options を宣言してこれを import する。同期スクリプト本体（`nix/papis-sync-script.nix`）は env
（`PAPIS_LIBRARY_DIR` / `PAPIS_REMOTE` / `RCLONE_CONFIG`）だけを読み、保存先も secret も知らない。
gdrive を NAS 等へ差し替えても sync-script の差し替えで済み、`programs.papis` 設定は不変。

依存の向きは **sync → library** の一方向。同期は「papis ライブラリが `libraryDir` に存在する」
ことを前提にするが、`programs.papis` は同期 backend を一切知らない。

### 本体と同期を `papis.enable` でまとめて出す（`referenceSync` 単一トグル）

旧構成は papis 本体を `gui`、同期を `referenceSync` と別 gate にしていたが、統合モジュールでは
`services.zettelkasten.papis.enable`（flake_public では `referenceSync` から注入）**1 本**で本体・
設定・同期をまとめて導入する。参照文献ワークフローは「本体があるのに同期が無い/その逆」に
意味が無く、まとめる方が凝集度が高い。副作用として、`gui=true` でも `referenceSync=false` の
環境（standalone `pomu-nixos` 等）では papis 本体も入らなくなる。WSL のような無効環境では papis も
sops も一切読み込まれない点は従来どおり。

### secret は vault が所有し、同期スクリプト自身が実行時に復号する

rclone.conf の token は添付同期・papis 同期でしか使わない **vault 専用 secret**。そこで
「唯一の消費者」である vault flake が暗号文（`secrets/rclone.yaml`）・受信者一覧（`.sops.yaml`）・
復号処理（`nix/with-rclone-secret.nix`）をすべて所有する。環境側に残るのは復号鍵だけ:

- **vault 側**: with-rclone-secret が同期スクリプトをラップし、実行のたびに「鍵発見
  （`SOPS_AGE_KEY(_FILE)` → `~/.ssh/id_ed25519` の ssh-to-age 変換）→ tmpfs へ復号 →
  `RCLONE_CONFIG` を向けて同期本体を実行 → 平文削除」を行う。secret 名 "rclone_conf" を
  知るのはここだけに閉じる。同期本体（bisync-lib / sync-script）は sops を知らないまま
  （`RCLONE_CONFIG` string シームを挟む逐次的凝集）。
- **環境側（各マシン）**: `.sops.yaml` の受信者に登録済みの秘密鍵を持つだけ。flake に
  秘密鍵は絶対に載らない（載るのは暗号文と公開鍵のみ）。

papis 同期（`referenceSync`）と Zettelkasten 添付同期（`zettelkastenSync`）は同じ secret を
共有するが、暗号文も復号処理も vault 側 1 箇所なので二重管理は無い。

`RCLONE_CONFIG` を明示した場合は復号をスキップしてそのパスを使う（escape hatch。平文
rclone.conf 運用や fork 利用者向け。`services.zettelkasten.rcloneConfigPath` も同じ穴に通じる）。
第三者の実行時利用は設計対象外（fork して個人固有部分を差し替える想定。
[zettelkasten-attachments-sync.md](./zettelkasten-attachments-sync.md#なぜ-vault-flake-側に置くのかnix-run-単独動作) 参照）。

## セキュリティモデル

- **OAuth scope は `drive.file`**（フルの `drive` ではない）。暗号化トークンは
  公開リポジトリに永続コミットされるため、万一 age 鍵が漏れても被害範囲を
  「rclone が作成したファイル」に限定する。代償として、Drive UI で手動作成した
  フォルダは rclone から見えない（フォルダは rclone に作らせる）
- **暗号化ファイルの公開は sops の設計どおり安全**。平文は絶対にコミットしない。
  復号・編集には受信者マシンの user SSH 秘密鍵（`~/.ssh/id_ed25519`）が必要
- **復号済み rclone.conf は同期中だけ存在**（tmpfs の一時ファイル、終了時に削除）。
  rclone が refresh 後の access token を書き戻しても破棄されるが、refresh token は
  長命で不変なので継続動作する

## 運用上の性質・既知の制約

- **削除は双方向伝播**。安全網は Drive のゴミ箱（既定で削除は trash 送り、30 日復元可）と
  bisync の `--max-delete`（既定 50% 超で中断）
- **watcher はローカル変更のみ検知**。他マシンの追加は次回の自分の同期時に pull される。
  pull した結果もローカル書き込みなので watcher が再発火するが、差分なしで収束する有界サイクル
- **初回 `--resync` は破壊的**。誤用（既存 baseline の上書き）はラッパースクリプトが
  baseline の存在を検知して中止する（`PAPIS_FORCE_RESYNC=1` で override）
- **空ディレクトリでは baseline を作れない**。bisync は空の listing を異常の兆候とみなし、
  空↔空で resync した後の同期を `Empty prior Path1 listing` で拒否する。よって初回 resync は
  **papis ライブラリに item が入った状態**で行う必要がある（空で始められない）。
  使い方の手順6・スモークテスト参照
- **Drive 側フォルダは rclone に作らせる**。scope=`drive.file` では Drive UI で手動作成した
  フォルダが rclone から見えず、未作成のまま resync すると `directory not found` になる。
  初回だけ `rclone mkdir gdrive:papis-library` で作る（以降は既存なので不要）
- **監視ディレクトリはこのモジュールが所有しない**。ライブラリは `papis add` が初めて作る。
  未作成時は起動ラッパーが正常終了(0)し、`Restart=on-failure` /
  `KeepAlive.SuccessfulExit=false` と組み合わせてクラッシュループを避ける
- **flake 評価には vault flake input 内の `secrets/rclone.yaml` が必要**（feature 有効な構成のみ）。
  この実体は vault リポジトリにコミット済みなので、`flake_public` は input 経由で常に参照できる。
  ローカルで vault を編集中に検証するときは `--override-input zettelkasten path:/path/to/zettelkasten`
  で差し替える。無効構成（WSL 等）は影響を受けない
