#!/usr/bin/env bash
# Publish an immutable cache release, without advancing a deployment channel.
set -euo pipefail
umask 077

if [[ ${1:-} == --self-check && $# == 1 ]]; then
  for dep in cmp gcloud jq mktemp nix rm sops stat; do
    if ! command -v "$dep" >/dev/null; then
      printf 'Missing publisher dependency: %s\n' "$dep" >&2
      exit 127
    fi
  done
  exit 0
fi

if (( $# != 5 )); then
  echo 'Usage: publish-cache.sh gs://CACHE_BUCKET gs://SIGNING_BUCKET/cache-signing.sops.json SHA DESKTOP_TOPLEVEL SPIN713_TOPLEVEL' >&2
  exit 2
fi
cache_bucket=$1
ciphertext=$2
revision=$3
desktop=$4
spin=$5
age_key=${SOPS_AGE_KEY_FILE:?set SOPS_AGE_KEY_FILE to the dedicated worker identity file}
[[ $cache_bucket =~ ^gs://[a-z0-9][a-z0-9-]+$ ]]
[[ $ciphertext =~ ^gs://[a-z0-9][a-z0-9-]+/cache-signing\.sops\.json$ ]]
[[ ${ciphertext%/*} != "$cache_bucket" ]]
[[ $revision =~ ^[0-9a-f]{40}$ ]]
[[ $desktop =~ ^/nix/store/[0-9a-z]{32}-nixos-system-nixos-desktop-[a-zA-Z0-9.\+-]+$ ]]
[[ $spin =~ ^/nix/store/[0-9a-z]{32}-nixos-system-nixos-spin713-[a-zA-Z0-9.\+-]+$ ]]
[[ -x $desktop/bin/switch-to-configuration && -x $spin/bin/switch-to-configuration ]]
[[ -f $age_key && ! -L $age_key && $(stat -c %u "$age_key") == "$EUID" && $(stat -c %a "$age_key") == 600 ]]

runtime_root=${RUNTIME_DIRECTORY:-/run}
[[ $(stat -f -c %T "$runtime_root") == tmpfs ]]
runtime=$(mktemp -d "$runtime_root/flake-cache-sign.XXXXXXXX")
cache_tmp=''
cleanup() {
  rm -rf -- "$runtime"
  if [[ -n $cache_tmp ]]; then rm -rf -- "$cache_tmp"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cache_tmp=$(mktemp -d "${TMPDIR:-/var/tmp}/flake-cache-stage.XXXXXXXX")
gcloud storage cp "$ciphertext" "$runtime/cache-signing.sops.json" --quiet
SOPS_AGE_KEY_FILE=$age_key sops --decrypt --extract '["signing_key"]' \
  --output "$runtime/signing.key" "$runtime/cache-signing.sops.json"
public_key=$(nix key convert-secret-to-public < "$runtime/signing.key")
key_name=${public_key%%:*}
[[ $key_name =~ ^flake-public-cache-[1-9][0-9]*$ ]]
[[ $public_key =~ ^[^:]+:[A-Za-z0-9+/]{43}=$ ]]

# Credentials stay outside the cache tree. The Nix cache store signs the NAR metadata
# during copy; the source /nix/store does not need global signing configuration.
nix copy --to "file://$cache_tmp?compression=zstd&secret-key=$runtime/signing.key" "$desktop" "$spin"
rm -f -- "$runtime/signing.key" "$runtime/cache-signing.sops.json"
cache_prefix="$cache_bucket/cache/$key_name"
# Publish archive data before any pointer can name this release. No overwrite or delete.
gcloud storage rsync "$cache_tmp" "$cache_prefix" --recursive --no-clobber --if-generation-match=0 --quiet
for top in "$desktop" "$spin"; do
  basename=${top##*/}
  narinfo=${basename%%-*}.narinfo
  gcloud storage cat "$cache_prefix/$narinfo" > "$runtime/$narinfo"
  cmp -- "$cache_tmp/$narinfo" "$runtime/$narinfo"
done

jq -n --arg commit "$revision" --arg key "$public_key" --arg cache "$cache_prefix" \
  --arg desktop "$desktop" --arg spin "$spin" \
  '{version:1,commit:$commit,cache:$cache,signing_public_key:$key,hosts:{"nixos-desktop":$desktop,"nixos-spin713":$spin}}' \
  > "$runtime/manifest.json"
manifest="$cache_bucket/releases/$revision.json"
# Repeating an identical publish is fine; a conflicting manifest must not be replaced.
if ! gcloud storage cp "$runtime/manifest.json" "$manifest" --content-type=application/json --if-generation-match=0 --quiet; then
  gcloud storage cat "$manifest" > "$runtime/existing.json"
  cmp -- "$runtime/manifest.json" "$runtime/existing.json"
fi
gcloud storage cat "$manifest" > "$runtime/published.json"
cmp -- "$runtime/manifest.json" "$runtime/published.json"
printf 'Published and verified %s\n' "$manifest"
