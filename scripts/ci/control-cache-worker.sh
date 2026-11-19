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
object() { python3 "$(dirname -- "${BASH_SOURCE[0]}")/gcs-object.py" "$@"; }
generation_or_zero() {
  local rc
  if object generation "$1"; then return 0; else rc=$?; fi
  if (( rc != 44 )); then return "$rc"; fi
  printf '0\n'
}

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
rc=0
object get "$manifest" > "$stage/release.json" || rc=$?
if (( rc == 44 )); then
  [[ $(state) == TERMINATED ]] || { echo 'Cache worker is not stopped; refusing to replace its request.' >&2; exit 1; }
  jq -n --arg commit "$commit" --arg run "$run" '{commit:$commit,run:$run}' > "$stage/request.json"
  pending="$bucket/requests/pending.json"
  generation=$(generation_or_zero "$pending")
  object put "$pending" "$stage/request.json" --if-generation-match "$generation"
  gcloud compute instances start "$instance" --zone="$zone" --async --quiet
  started=1
  deadline=$((SECONDS + 17400))
  completed=0
  while (( SECONDS < deadline )); do
    if object get "$bucket/status/$run.json" > "$stage/status.json" 2> "$stage/status-error"; then
      jq -e --arg sha "$commit" '.commit == $sha and .exit_code == 0' "$stage/status.json" >/dev/null
      completed=1
      break
    else
      rc=$?
      if (( rc != 44 )); then cat "$stage/status-error" >&2; exit "$rc"; fi
    fi
    sleep 40
  done
  (( completed )) || { echo 'Cache worker timed out without publishing a success status.' >&2; exit 1; }
  object get "$manifest" > "$stage/release.json"
elif (( rc != 0 )); then
  exit "$rc"
fi
bash "$(dirname -- "${BASH_SOURCE[0]}")/promote-cache.sh" "$bucket" "$commit"
