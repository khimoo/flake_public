# papis ライブラリの Google Drive 同期（設計判断）

設定ファイル:
- `modules/home-manager/papis/default.nix`（app と sync の合成。feature フラグでの条件 import）
- `modules/home-manager/papis/app.nix`（papis 本体と `programs.papis` 設定。gui feature で導入）
- `modules/home-manager/papis/sync.nix`（同期スクリプト・scheduler・secret）
- `.sops.yaml` / `secrets/rclone.yaml`（暗号化された rclone.conf）

使い方・鍵運用の手順は [../howtouse/papis-gdrive-sync.md](../howtouse/papis-gdrive-sync.md) を参照。

## 全体構成

```
papis add ──> ~/papis-library/<item>/{info.yaml, *.pdf} ──(watchexec 監視)──> papis-sync
                                                                                 │
                                            rclone bisync (--config 復号済み rclone.conf)
                                                                                 │
                                                                    Google Drive:papis-library
```

同期対象は `nixos-desktop` / `nixos-spin713`、および将来の macOS（会社 PC）。
全マシンで **home-manager sops** により *ユーザ層* で復号する統一構成。

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
`~/papis-library` を丸ごと 1 本の rclone bisync で同期すれば両方カバーできる。

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

### 復号は home-manager（ユーザ層）で統一。NixOS システム側で行わない

当初案は「NixOS システム側で `/run/secrets` に復号」だったが、macOS（NixOS 層が無い）
を対象に含めた時点で以下の理由から **全マシン home-manager sops に統一**した:

- **レイヤリング**: rclone/Google Drive のトークンは *ユーザの関心事*。システム層が
  ユーザの Drive トークンを知る必要はない。ユーザ層で復号する方が関心事の分離として正しい
- **単一の secret パス源**: 復号先は全環境で `config.sops.secrets."rclone_conf".path`。
  `/run/secrets`（NixOS）と macOS 固有パスに分岐する必要がなく、同期スクリプトは
  この属性だけを参照する（提供側=sops、消費側=スクリプトの **依存性逆転**）。
  プラットフォーム差は sops-nix が内部で吸収する
- **機構の一本化**: NixOS ホストと macOS で同一の復号機構になり、分岐と重複が減る

トレードオフ: 各マシンにユーザ復号鍵が要る。ただし macOS 対応時点でどのみち必要で、
下記のとおり既存の user SSH 鍵を流用するので新しい鍵は配らない。

### 復号鍵は各マシンの user SSH 鍵（ssh-to-age）

`sops.age.sshKeyPaths = [ "~/.ssh/id_ed25519" ]`。git/リモートビルドで各マシンに
既にある ed25519 ユーザ鍵を age に変換して使い、新しい鍵の配布を避ける。
マシン単位の鍵なので、廃棄時はそのマシンの受信者を外して `sops updatekeys` すれば失効できる。

### app 本体と sync を同一ディレクトリ（`papis/`）に置く

papis 本体＋設定（`app.nix`）とライブラリ同期（`sync.nix`）を、ドメイン単位で 1 つの
`papis/` ディレクトリにまとめる。ディレクトリ名は volatile な同期 backend
（rclone-gdrive）でも特定ツール名でもなく、参照文献マネージャという安定したドメイン
（papis）で付ける。gdrive を NAS 等へ差し替えても `sync.nix` の差し替えで済み、
`app.nix`・ディレクトリ名は不変。

依存の向きは **sync → library** の一方向。`sync.nix` は「papis ライブラリ
`~/papis-library` が存在する」ことを前提にするが、`app.nix` は同期 backend を
一切知らない。空間的にまとめても gate は独立（app=`gui`、sync=`referenceSync`）なので、
この一方向依存は崩れない。

### feature フラグ＋条件 import で無効環境の footprint をゼロにする

`papis` モジュールは全環境共通の `homeModules` に登録するが、`app.nix` は
`gui` feature で self-gate し、`default.nix` は `settings.features.referenceSync` が
真のときだけ `sops-nix` ホームモジュールと `sync.nix` を import する。WSL のような
GUI 無効・同期非対応の環境では、papis も sops も含め一切読み込まれない。

## セキュリティモデル

- **OAuth scope は `drive.file`**（フルの `drive` ではない）。暗号化トークンは
  公開リポジトリに永続コミットされるため、万一 age 鍵が漏れても被害範囲を
  「rclone が作成したファイル」に限定する。代償として、Drive UI で手動作成した
  フォルダは rclone から見えない（フォルダは rclone に作らせる）
- **暗号化ファイルの公開は sops の設計どおり安全**。平文は絶対にコミットしない。
  復号・編集には受信者マシンの user SSH 秘密鍵（`~/.ssh/id_ed25519`）が必要
- **rclone.conf は読み取り専用**（sops 復号先）。refresh 後の access token を
  書き戻せず warning が出るが、refresh token は長命なので継続動作する

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
- **flake 評価には `secrets/rclone.yaml` の実体が必要**（feature 有効な構成のみ）。
  未作成だと該当ホストの `nixos-rebuild` / `nix flake check` は評価エラーになる。
  無効構成（WSL 等）は影響を受けない
