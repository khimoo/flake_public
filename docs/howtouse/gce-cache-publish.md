# GCE ビルドから Nix キャッシュを公開する

実装: [`publish-cache.sh`](../../scripts/ci/publish-cache.sh) / [スモークテスト](../../tests/flake-cache-publisher.sh)

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

この段階では Actions からの VM 起動、`stable` の切り替え、実機の取得・適用はつないでいない。
