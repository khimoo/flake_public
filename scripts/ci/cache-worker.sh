#!/usr/bin/env bash
set -euo pipefail
umask 077
export HOME=$STATE_DIRECTORY
export CLOUDSDK_CONFIG=$STATE_DIRECTORY/gcloud
# The full boot disk and store persist across runs; only /run contains decrypted material.
export SOPS_AGE_KEY_FILE=$STATE_DIRECTORY/age.key
if [[ ! -e $SOPS_AGE_KEY_FILE ]]; then
  age-keygen -o "$SOPS_AGE_KEY_FILE" 2>/dev/null
fi
printf 'FLAKE_CACHE_AGE_RECIPIENT=%s\n' "$(age-keygen -y "$SOPS_AGE_KEY_FILE")"
project_number=$(curl -fsS --max-time 20 -H 'Metadata-Flavor: Google' \
  http://169.254.169.254/computeMetadata/v1/project/numeric-project-id)
[[ $project_number =~ ^[0-9]+$ ]]
cache=gs://flake-public-cache-$project_number
signing=gs://flake-public-signing-$project_number/cache-signing.sops.json
request=$RUNTIME_DIRECTORY/request.json
if ! gcloud storage cat "$cache/requests/pending.json" > "$request"; then
  echo 'FLAKE_CACHE_IDLE: no readable request; no build started'
  exit 0
fi
sha=$(jq -er '.commit | select(type == "string" and test("^[0-9a-f]{40}$"))' "$request")
run=$(jq -er '.run | select(type == "string" and test("^[0-9]+-[0-9]+$"))' "$request")
[[ $sha =~ ^[0-9a-f]{40}$ && $run =~ ^[0-9]+-[0-9]+$ ]]
status="$cache/status/$run.json"
finish() {
  local rc=$?
  trap - EXIT
  jq -n --arg commit "$sha" --argjson exit_code "$rc" '{commit:$commit,exit_code:$exit_code}' \
    > "$RUNTIME_DIRECTORY/status.json"
  if ! gcloud storage cp "$RUNTIME_DIRECTORY/status.json" "$status" --quiet --if-generation-match=0; then
    printf 'FLAKE_CACHE_STATUS_UPLOAD_FAILED %s\n' "$run" >&2
  fi
  printf 'FLAKE_CACHE_END run=%s rc=%s\n' "$run" "$rc"
  systemctl --no-block poweroff || true
  exit "$rc"
}
trap finish EXIT
printf 'FLAKE_CACHE_BUILD run=%s commit=%s\n' "$run" "$sha"
build_home=/var/lib/flake-build
as_builder() { runuser -u flake-build -- env HOME="$build_home" "$@"; }
checkout=$build_home/flake_public
if [[ ! -d $checkout/.git ]]; then
  as_builder git clone --no-tags --single-branch --branch main https://github.com/khimoo/flake_public.git "$checkout"
fi
as_builder git -C "$checkout" fetch --no-tags https://github.com/khimoo/flake_public.git refs/heads/main
# Only build a revision of main, not a branch or arbitrary externally supplied code.
as_builder git -C "$checkout" merge-base --is-ancestor "$sha" FETCH_HEAD
as_builder git -C "$checkout" checkout --detach --force "$sha"
root_dir=$build_home/releases/$sha
as_builder mkdir -p "$root_dir"
cd "$checkout"
desktop=$(as_builder nix build --no-update-lock-file --out-link "$root_dir/desktop" \
  --print-out-paths .#nixosConfigurations.nixos-desktop.config.system.build.toplevel)
spin=$(as_builder nix build --no-update-lock-file --out-link "$root_dir/spin713" \
  --print-out-paths .#nixosConfigurations.nixos-spin713.config.system.build.toplevel)
cd "$STATE_DIRECTORY"
bash "$PUBLISH_CACHE" "$cache" "$signing" "$sha" "$desktop" "$spin"
