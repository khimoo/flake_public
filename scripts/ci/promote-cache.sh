#!/usr/bin/env bash
# Promote a verified manifest. The smoke root is deliberately not the production bucket.
set -euo pipefail
umask 077
root=${1:?missing release root}
commit=${2:?missing commit}
[[ $root =~ ^gs://flake-public-cache-[0-9]+$ || $root =~ ^gs://flake-public-smoke-[0-9]+/runs/[0-9]+-[0-9]+$ ]]
[[ $commit =~ ^[0-9a-f]{40}$ ]]
[[ $(git rev-parse --verify "$commit^{commit}") == "$commit" ]]
object() { python3 "$(dirname -- "${BASH_SOURCE[0]}")/gcs-object.py" "$@"; }
stage=$(mktemp -d "${RUNNER_TEMP:-/var/tmp}/flake-cache-promote.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
release="releases/$commit.json"
object get "$root/$release" > "$stage/release.json"
jq -e --arg sha "$commit" --arg root "$root" '
  .version == 1 and .commit == $sha and (.cache | startswith($root + "/cache/")) and
  (.hosts["nixos-desktop"] | test("^/nix/store/[a-z0-9]{32}-nixos-system-nixos-desktop-[a-zA-Z0-9.+-]+$")) and
  (.hosts["nixos-spin713"] | test("^/nix/store/[a-z0-9]{32}-nixos-system-nixos-spin713-[a-zA-Z0-9.+-]+$"))
' "$stage/release.json" >/dev/null

stable="$root/channels/stable.json"
rc=0
generation=$(object generation "$stable") || rc=$?
if (( rc == 44 )); then
  generation=0
elif (( rc != 0 )); then
  exit "$rc"
fi
if [[ $generation != 0 ]]; then
  object get "$stable" --generation "$generation" > "$stage/old.json"
  old=$(jq -er '.commit | select(type == "string" and test("^[0-9a-f]{40}$"))' "$stage/old.json")
  if [[ $old == "$commit" ]]; then exit 0; fi
  git merge-base --is-ancestor "$old" "$commit" || { echo 'Refusing to roll stable back.' >&2; exit 1; }
fi
jq -n --arg commit "$commit" --arg release "$release" \
  '{version:1,commit:$commit,release:$release}' > "$stage/stable.json"
object put "$stable" "$stage/stable.json" --if-generation-match "$generation"
object get "$stable" > "$stage/published.json"
cmp -- "$stage/published.json" "$stage/stable.json"
printf 'Promoted and verified stable: %s\n' "$commit"
