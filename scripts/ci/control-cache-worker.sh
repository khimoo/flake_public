#!/usr/bin/env bash
set -euo pipefail
umask 077
bucket=${CACHE_BUCKET:?missing CACHE_BUCKET}
zone=${CACHE_VM_ZONE:?missing CACHE_VM_ZONE}
commit=${GITHUB_SHA:?missing GITHUB_SHA}
run="$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
[[ $bucket =~ ^gs://flake-public-cache-[0-9]+$ && $commit =~ ^[0-9a-f]{40}$ && $run =~ ^[0-9]+-[0-9]+$ ]]
[[ $(git rev-parse HEAD) == "$commit" ]]
instance=flake-cache-worker
state() { gcloud compute instances describe "$instance" --zone="$zone" --format='value(status)'; }

stage=$(mktemp -d "${RUNNER_TEMP:-/var/tmp}/flake-cache-control.XXXXXXXX")
started=0
cleanup() {
  if (( started )); then
    gcloud compute instances stop "$instance" --zone="$zone" --async --quiet || true
  fi
  rm -rf -- "$stage"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

manifest="$bucket/releases/$commit.json"
if ! gcloud storage cat "$manifest" > "$stage/release.json"; then
  [[ $(state) == TERMINATED ]] || { echo 'Cache worker is not stopped; refusing to replace its request.' >&2; exit 1; }
  jq -n --arg commit "$commit" --arg run "$run" '{commit:$commit,run:$run}' > "$stage/request.json"
  gcloud storage cp "$stage/request.json" "$bucket/requests/pending.json" --quiet
  started=1
  gcloud compute instances start "$instance" --zone="$zone" --async --quiet
  deadline=$((SECONDS + 17400))
  completed=0
  while (( SECONDS < deadline )); do
    if gcloud storage cat "$bucket/status/$run.json" > "$stage/status.json" 2>/dev/null; then
      jq -e --arg sha "$commit" '.commit == $sha and .exit_code == 0' "$stage/status.json" >/dev/null
      completed=1
      break
    fi
    sleep 40
  done
  (( completed )) || { echo 'Cache worker timed out without publishing a success status.' >&2; exit 1; }
  gcloud storage cat "$manifest" > "$stage/release.json"
fi
jq -e --arg sha "$commit" --arg bucket "$bucket" '
  .version == 1 and .commit == $sha and (.cache | startswith($bucket + "/cache/")) and
  (.hosts["nixos-desktop"] | test("^/nix/store/[a-z0-9]{32}-nixos-system-nixos-desktop-")) and
  (.hosts["nixos-spin713"] | test("^/nix/store/[a-z0-9]{32}-nixos-system-nixos-spin713-"))
' "$stage/release.json" >/dev/null

stable="$bucket/channels/stable.json"
if gcloud storage objects describe "$stable" --format='value(generation)' > "$stage/generation" 2> "$stage/describe-error"; then
  generation=$(<"$stage/generation")
  [[ $generation =~ ^[0-9]+$ ]]
  gcloud storage cat "$stable#$generation" > "$stage/old.json"
  old=$(jq -er '.commit | select(type == "string" and test("^[0-9a-f]{40}$"))' "$stage/old.json")
  if [[ $old == "$commit" ]]; then exit 0; fi
  git merge-base --is-ancestor "$old" "$commit" || { echo 'Refusing to roll stable back.' >&2; exit 1; }
else
  # An authorization or a network error is not an absent stable object.
  if ! grep -Ei '(^|[^0-9])404([^0-9]|$)|No URLs matched|could not find.*object' "$stage/describe-error"; then
    cat "$stage/describe-error" >&2
    exit 1
  fi
  generation=0
fi
jq -n --arg commit "$commit" --arg release "releases/$commit.json" \
  '{version:1,commit:$commit,release:$release}' > "$stage/stable.json"
gcloud storage cp "$stage/stable.json" "$stable" --quiet --content-type=application/json --if-generation-match="$generation"
gcloud storage cat "$stable" > "$stage/published.json"
cmp -- "$stage/published.json" "$stage/stable.json"
printf 'Promoted and verified stable: %s\n' "$commit"
