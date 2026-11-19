# 利用目的: CI が非公開 GCS バケットへ公開した署名済み NixOS クロージャを、ビルドなしで署名検証・取得・適用する（docs/howtouse/gce-cache-publish.md）。
role = True
needs = ["linux"]

def user_config(owner):
    env = {
        "FLAKE_DEPLOY_BUCKET": owner.flake_cache_bucket,
        "FLAKE_DEPLOY_PUBLIC_KEY": owner.flake_cache_public_key,
        "FLAKE_DEPLOY_READER_SA": owner.flake_cache_reader_sa,
        "FLAKE_DEPLOY_SCRIPT": repoPath("scripts/ci/flake-deploy.py"),
        "FLAKE_DEPLOY_GCS_OBJECT": repoPath("scripts/ci/gcs-object.py"),
    }
    return {"home": {"home.packages": [shellAppEnv(
        "flake-deploy",
        [pkg("python3"), pkg("google-cloud-sdk"), pkg("git")],
        env,
        repoText("modules/home-manager/dev/flake-deploy.sh"),
    )]}}
