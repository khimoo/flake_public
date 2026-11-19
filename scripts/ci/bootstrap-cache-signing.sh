#!/usr/bin/env bash
# The public age recipient is printed once per boot by the dedicated worker.
set -euo pipefail
umask 077
if (( $# != 3 )); then
  echo 'Usage: bootstrap-cache-signing.sh gs://SIGNING_BUCKET AGE_RECIPIENT SIGNING_KEY_NAME' >&2
  exit 2
fi
bucket=$1
recipient=$2
name=$3
[[ $bucket =~ ^gs://flake-public-signing-[0-9]+$ ]]
[[ $recipient =~ ^age1[0-9a-z]+$ ]]
[[ $name =~ ^flake-public-cache-[1-9][0-9]*$ ]]
runtime=${XDG_RUNTIME_DIR:-/dev/shm}
[[ $(stat -f -c %T "$runtime") == tmpfs ]]
stage=$(mktemp -d "$runtime/flake-cache-bootstrap.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
nix key generate-secret --key-name "$name" > "$stage/key"
nix key convert-secret-to-public < "$stage/key" > "$stage/public"
jq -Rs '{signing_key: rtrimstr("\n")}' < "$stage/key" > "$stage/key.json"
sops --config /dev/null encrypt --age "$recipient" --output-type json "$stage/key.json" > "$stage/encrypted.json"
rm -- "$stage/key" "$stage/key.json"
gcloud storage cp "$stage/encrypted.json" "$bucket/cache-signing.sops.json" --content-type=application/json --if-generation-match=0 --quiet
gcloud storage cat "$bucket/cache-signing.sops.json" > "$stage/readback.json"
cmp -- "$stage/encrypted.json" "$stage/readback.json"
cat "$stage/public"
