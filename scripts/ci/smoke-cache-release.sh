#!/usr/bin/env bash
# Real WIF and GCS, small Nix fixtures, no VM or production secret involved.
set -euo pipefail
umask 077
bucket=${CACHE_SMOKE_BUCKET:?missing smoke-only bucket}
run="$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
[[ $bucket =~ ^gs://flake-public-smoke-[0-9]+$ && $run =~ ^[0-9]+-[0-9]+$ ]]
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
object() { python3 "$repo/gcs-object.py" "$@"; }
root="$bucket/runs/$run"
stable="$root/channels/stable.json"
work=$(mktemp -d "${RUNNER_TEMP:-/var/tmp}/flake-smoke.XXXXXXXX")
keys=$(mktemp -d /dev/shm/flake-smoke.XXXXXXXX)
trap 'rm -rf -- "$work" "$keys"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for endpoint in get generation; do
  rc=0
  object "$endpoint" "$stable" > "$work/absent.out" 2> "$work/absent.err" || rc=$?
  [[ $rc == 44 ]]
  grep -Fq 'HTTP 404' "$work/absent.err"
  rc=0
  object "$endpoint" "$bucket/runs/policy/forbidden.json" > "$work/denied.out" 2> "$work/denied.err" || rc=$?
  [[ $rc == 1 ]]
  grep -Fq 'HTTP 403' "$work/denied.err"
done
if gcloud storage ls "$bucket" > "$work/list.out" 2> "$work/list.err"; then
  echo 'Unexpected access to list the smoke bucket' >&2
  exit 1
fi
grep -Fq 'storage.objects.list' "$work/list.err"
printf '403 and 404 distinguished; bucket listing denied.\n'

request="$root/requests/pending.json"
rc=0
object generation "$request" > /dev/null 2>&1 || rc=$?
[[ $rc == 44 ]]
printf '{"phase":"first"}\n' > "$work/request.json"
object put "$request" "$work/request.json" --if-generation-match 0
request_gen=$(object generation "$request")
cmp -- "$work/request.json" <(object get "$request" --generation "$request_gen")
printf '{"phase":"second"}\n' > "$work/request.json"
object put "$request" "$work/request.json" --if-generation-match "$request_gen"
cmp -- "$work/request.json" <(object get "$request")

key_name="flake-public-smoke-$run"
nix key generate-secret --key-name "$key_name" > "$keys/signing.key"
public=$(nix key convert-secret-to-public < "$keys/signing.key")
mkdir -p "$work/cache" "$work/download" "$work/tree"
for host in nixos-desktop nixos-spin713; do
  tree="$work/tree/nixos-system-$host-smoke"
  mkdir -p "$tree/bin"
  printf '#!/bin/sh\nexit 0\n' > "$tree/bin/switch-to-configuration"
  chmod +x "$tree/bin/switch-to-configuration"
done
desktop=$(nix-store --add "$work/tree/nixos-system-nixos-desktop-smoke")
spin=$(nix-store --add "$work/tree/nixos-system-nixos-spin713-smoke")
nix copy --to "file://$work/cache?compression=zstd&secret-key=$keys/signing.key" "$desktop" "$spin"
rm -- "$keys/signing.key"
cache="$root/cache/$key_name"
while IFS= read -r -d '' file; do
  relative=${file#"$work/cache/"}
  object put "$cache/$relative" "$file" --if-generation-match 0
  mkdir -p -- "$work/download/$(dirname -- "$relative")"
  object get "$cache/$relative" > "$work/download/$relative"
  cmp -- "$file" "$work/download/$relative"
done < <(find "$work/cache" -type f -print0)
nix store verify --store "file://$work/download" --sigs-needed 1 --option trusted-public-keys "$public" "$desktop" "$spin"
printf 'Both fixture closures verified after GCS download with the temporary key.\n'

current=$(git rev-parse HEAD)
previous=$(git rev-parse HEAD^)
# Real promotion script must not advance a channel without a manifest.
if bash "$repo/promote-cache.sh" "$root" "$previous"; then
  echo 'Promotion succeeded before release creation' >&2
  exit 1
fi
rc=0
object generation "$stable" > /dev/null 2>&1 || rc=$?
[[ $rc == 44 ]]
for sha in "$previous" "$current"; do
  jq -n --arg commit "$sha" --arg key "$public" --arg cache "$cache" --arg desktop "$desktop" --arg spin "$spin" \
    '{version:1,commit:$commit,cache:$cache,signing_public_key:$key,hosts:{"nixos-desktop":$desktop,"nixos-spin713":$spin}}' > "$work/release.json"
  object put "$root/releases/$sha.json" "$work/release.json" --if-generation-match 0
  bash "$repo/promote-cache.sh" "$root" "$sha"
done
rc=0
object get "$stable" > "$work/stable.json"
object put "$stable" "$work/stable.json" --if-generation-match 0 2> "$work/conflict.err" || rc=$?
[[ $rc == 12 ]]
grep -Fq 'HTTP 412' "$work/conflict.err"
if bash "$repo/promote-cache.sh" "$root" "$previous" 2> "$work/rollback.err"; then
  echo 'Rollback unexpectedly succeeded' >&2
  exit 1
fi
grep -Fq 'Refusing to roll stable back.' "$work/rollback.err"
object get "$stable" | jq -e --arg sha "$current" '.commit == $sha' >/dev/null
printf 'Smoke completion: manifest ordering, first promotion, forward promotion, stale generation rejection, and rollback rejection.\n'
