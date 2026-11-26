#!/usr/bin/env bash
# Publish an immutable cache release, without advancing a deployment channel.
set -euo pipefail
umask 077

if [[ ${1:-} == --self-check && $# == 1 ]]; then
  for dep in cmp gcloud jq mkdir mktemp nix rm sops stat; do
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

cache_prefix="$cache_bucket/cache/$key_name"

# List already-published .narinfo objects (non-recursive) so unchanged store paths
# are not re-compressed, re-signed, or re-scanned on every release.
ls_out="$runtime/existing.list"
ls_err="$runtime/existing.err"
if gcloud storage ls "$cache_prefix/" > "$ls_out" 2> "$ls_err"; then
  :
else
  ls_rc=$?
  ls_err_text=$(<"$ls_err")
  if [[ $ls_err_text == *"matched no objects"* ]]; then
    : > "$ls_out"
  else
    printf '%s\n' "$ls_err_text" >&2
    exit "$ls_rc"
  fi
fi

declare -A published=()
has_cache_info=0
while IFS= read -r uri; do
  uri=${uri%$'\r'}
  name=${uri##*/}
  if [[ $name == nix-cache-info ]]; then
    has_cache_info=1
  elif [[ $name =~ ^([0-9a-z]{32})\.narinfo$ ]]; then
    published[${BASH_REMATCH[1]}]=1
  fi
done < "$ls_out"

closure_list="$runtime/closure.paths"
nix path-info --recursive "$desktop" "$spin" > "$closure_list"

declare -A seen=()
missing_paths=()
while IFS= read -r store_path; do
  [[ -n $store_path ]] || continue
  [[ -z ${seen[$store_path]:-} ]] || continue
  seen[$store_path]=1
  base=${store_path##*/}
  hash=${base%%-*}
  if [[ -z ${published[$hash]:-} ]]; then
    missing_paths+=("$store_path")
  fi
done < "$closure_list"

printf 'Cache closure: %d total, %d new (already published: %d)\n' \
  "${#seen[@]}" "${#missing_paths[@]}" "$((${#seen[@]} - ${#missing_paths[@]}))"

upload_chunks() {
  local dest=$1
  shift
  local total=$#
  local i=0
  local chunk=500
  while (( i < total )); do
    gcloud storage cp --no-clobber --if-generation-match=0 --quiet "${@:i+1:chunk}" "$dest"
    i=$((i + chunk))
  done
}

# Credentials stay outside the cache tree. The Nix cache store signs the NAR metadata
# during copy; the source /nix/store does not need global signing configuration.
if (( ${#missing_paths[@]} > 0 )); then
  total=${#missing_paths[@]}
  i=0
  chunk=500
  while (( i < total )); do
    nix copy --no-recursive \
      --to "file://$cache_tmp?compression=zstd&secret-key=$runtime/signing.key" \
      "${missing_paths[@]:i:chunk}"
    i=$((i + chunk))
  done
fi
rm -f -- "$runtime/signing.key" "$runtime/cache-signing.sops.json"

# Publish NAR payloads before any .narinfo can reference them, and before any
# release manifest can point to this cache. No overwrite or delete.
shopt -s nullglob
nar_files=("$cache_tmp"/nar/*)
if (( ${#nar_files[@]} > 0 )); then
  upload_chunks "$cache_prefix/nar/" "${nar_files[@]}"
fi
meta_files=("$cache_tmp"/*.narinfo)
if (( has_cache_info == 0 )) && [[ -f $cache_tmp/nix-cache-info ]]; then
  meta_files=("$cache_tmp/nix-cache-info" "${meta_files[@]}")
fi
if (( ${#meta_files[@]} > 0 )); then
  upload_chunks "$cache_prefix/" "${meta_files[@]}"
fi
shopt -u nullglob

verify_dir="$runtime/verify"
mkdir -p "$verify_dir"
gcloud storage cat "$cache_prefix/nix-cache-info" > "$verify_dir/nix-cache-info"
for top in "$desktop" "$spin"; do
  basename=${top##*/}
  narinfo=${basename%%-*}.narinfo
  gcloud storage cat "$cache_prefix/$narinfo" > "$verify_dir/$narinfo"
  if [[ -f $cache_tmp/$narinfo ]]; then
    cmp -- "$cache_tmp/$narinfo" "$verify_dir/$narinfo"
  else
    nix store verify --no-contents --sigs-needed 1 \
      --option trusted-public-keys "$public_key" \
      --store "file://$verify_dir" "$top"
  fi
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
