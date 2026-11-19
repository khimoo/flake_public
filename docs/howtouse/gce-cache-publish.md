# GCE ビルドから Nix キャッシュを公開する

実装: [`publish-cache.sh`](../../scripts/ci/publish-cache.sh) / [スモークテスト](../../tests/flake-cache-publisher.sh) / [`flake-deploy.py`](../../scripts/ci/flake-deploy.py) / [クライアント単体テスト](../../tests/flake-deploy.py) / [`deploy_from_cache.star`](../../config/elements/deploy_from_cache.star)

GitHub の lock 更新・検証は [検証ガイド](./validation.md#github-actions-で依存を更新する) を参照。この手順はビルド済みクロージャの公開までを扱い、既存の [`nixos-gce`](./gce-offload.md) や実機には適用しない。

## 署名前の準備

- ビルド専用の VM を使う。公開用サービスアカウントには、成果物バケットへのオブジェクト作成・読み取りと、別の非公開バケットの `cache-signing.sops.json` の読み取りだけを付与する。上書きや削除は許可しない。2つのバケットで均一なバケットレベルアクセスと公開アクセス防止を有効にする。
- VM 専用の age 受信者を用意し、秘密の identity ファイルは VM で実行するユーザーの所有・0600 とする。既存の個人用 age 鍵は VM に渡さない。VM の永続ディスクやスナップショットには専用 age 鍵が残るため、アクセスを制限する。
- Nix の署名鍵を `flake-public-cache-1` のように版を含む名前で作る。秘密鍵を JSON の `signing_key` として専用 age 受信者に対し SOPS で暗号化し、暗号文だけを署名用バケットの `cache-signing.sops.json` に置く。平文は `/run` などの tmpfs で扱い、公開リポジトリ、Nix store、VM メタデータ、ログに載せない。署名時にもスクリプトが tmpfs に復号し、キャッシュ作成後に削除する。

## 公開する

専用 VM 上で、対象の `main` コミットをクリーンな checkout に固定し、`nix`、`sops`、`gcloud`、`jq` を使える状態で実行する。`gcloud` は専用 VM のサービスアカウントで認証する。`CACHE_BUCKET`、`SIGNING_BUCKET` は `gs://` から始まるそれぞれのバケット URI、`SOPS_AGE_KEY_FILE` は**専用**の age identity のファイルを指定する。

```sh
set -e
sha=$(git rev-parse HEAD)
desktop=$(nix build --no-update-lock-file --out-link result-desktop --print-out-paths \
  .#nixosConfigurations.nixos-desktop.config.system.build.toplevel)
spin=$(nix build --no-update-lock-file --out-link result-spin713 --print-out-paths \
  .#nixosConfigurations.nixos-spin713.config.system.build.toplevel)
bash scripts/ci/publish-cache.sh "$CACHE_BUCKET" \
  "$SIGNING_BUCKET/cache-signing.sops.json" "$sha" "$desktop" "$spin"
```

`cache/<署名鍵名>/` に署名済み Nix バイナリキャッシュを追加する。上書きせず、両ホストの `.narinfo` を読み戻してから `releases/<SHA>.json` を作る。同じ内容の再公開は成功し、既存のマニフェストと異なる場合は失敗する。キャッシュの作業領域も使うので、`TMPDIR` はクロージャ本体と作業領域を置けるディスクに指定する。

マニフェストの公開鍵は鍵名を識別する情報であり、実機が自動で信頼してよい鍵ではない。実機の信頼済み公開鍵は別途管理する。鍵を差し替えるときは版を上げ、信頼済み公開鍵の入れ替えと古い配布版の扱いを先に決める。

## 専用 VM と Actions を設定する

[専用イメージ](../../hosts/flake-cache-worker/image.nix) を flake と同じ nixpkgs でビルドします。専用 VM `flake-cache-worker` は SSH を開けず、永続ディスク上の `/nix/store` を次の起動にも使います。既存の `nixos-gce` は使いません。

```sh
nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake ("path:" + toString ./.); in
  (f.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/flake-cache-worker/image.nix ];
  }).config.system.build.googleComputeImage'
```

ワーカーを更新する前に、同じ式の末尾を `config.system.build.toplevel` に変えてビルドし、出力パスを `bash tests/flake-worker-unit.sh "$toplevel"` に渡します。このテストは生成された systemd ユニットから公開コマンドを取り出し、クロージャに含まれることと、空の環境から `--self-check` が通ることを確認します。VMでも各ビルド要求に対して先に同じ自己診断を行い、失敗した場合はビルド前に終了します。

イメージを更新するときは既存の起動ディスクを消さないでください。`/nix/store` のビルド成果物とワーカー専用 age identity の両方が載っています。同じディスク上で修正版に切り替え、再実行前に前回対象の `releases/<SHA>/` の出力リンクを確認します。VMを削除する方法を取る場合は、起動ディスクの自動削除設定を先に確認してください。

1. イメージを GCE に UEFI イメージとして取り込み、VM に公開専用 SA を付けます。初回起動ではビルドせず、シリアル出力に `FLAKE_CACHE_AGE_RECIPIENT` が出ます。秘密の age identity は VM に残ります。
2. 管理者の環境から [bootstrap-cache-signing.sh](../../scripts/ci/bootstrap-cache-signing.sh) に署名バケット URI、シリアル出力の公開受信者、`flake-public-cache-1` を渡すと、SOPS 暗号文だけを GCS に登録します。出力するのは実機で信頼設定する公開鍵です。
3. WIF は対象リポジトリの `main` と [配布ワークフロー](../../.github/workflows/publish-nixos-cache.yml) だけに許可します。Actions の制御 SA は、この VM の参照・起動・停止、ビルド要求と `stable` の更新、結果の読み取りだけを行います。署名用バケットは読めません。
4. Actions の変数 `FLAKE_CACHE_PROJECT`、`FLAKE_CACHE_WIF_PROVIDER`、`FLAKE_CACHE_CONTROLLER`、`FLAKE_CACHE_ZONE`、`FLAKE_CACHE_BUCKET` を設定します。最初は `verify=true` で VM を起動せずに認証を確認します。`FLAKE_CACHE_PUBLISH_ENABLED=true` にすると `main` の更新でビルドが起動し、成功した新しいコミットだけを `stable` にします。

## 実機で取得・適用する

実機（`nixos-spin713`・`nixos-desktop`）は利用目的 `deploy_from_cache` を選ぶと、`flake-deploy` コマンドが入ります（バケット URI・信頼済み公開鍵・読取専用 SA は [config/owner.toml](../../config/owner.toml) で管理）。

### 初回認証

プロジェクトの既定制約（`constraints/iam.disableServiceAccountKeyCreation`）に従い、長命な SA 鍵ファイルは作らず、ユーザーの `gcloud` 認証から読取専用 SA（`flake-cache-reader`、`cache/`・`releases/`・`channels/stable.json` のみ `roles/storage.objectViewer`）へ impersonate して短命トークンを取得します。各実機で初回だけ実行します。

```sh
gcloud auth login
```

### 確認・取得・適用

普段の適用では `git pull` も flake の再評価もビルドも行いません。取得できない場合はビルドへフォールバックせず失敗します。最初は `nixos-spin713` で `test` してから `switch` し、問題なければ同じコミットを `nixos-desktop` へ適用します。

```sh
# 稼働中の revision と公開済み stable の差分を確認
flake-deploy status

# 署名検証のみ（取り込み・適用はしない）
flake-deploy verify

# 検証済みクロージャを /nix/store へ取り込むのみ（適用はしない）
flake-deploy fetch

# verify / fetch で確認したコミット SHA を固定して一時適用・恒久適用
flake-deploy test --commit <40桁SHA>
flake-deploy switch --commit <40桁SHA>
```

稼働中の revision より古い版への切り替えはローカルの Git 履歴（既定 `/etc/nixos`）で拒否します。意図的に過去の公開版へ戻す場合は `--commit <過去の40桁SHA> --allow-rollback` を明示します。未コミットの変更を手元で試す場合は、従来どおり `nixos-rebuild test --flake .#<ホスト名>` を使います。
