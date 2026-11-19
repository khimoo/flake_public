#!/usr/bin/env bash
# Test real Nix/SOPS operations, with an isolated directory acting as Cloud Storage.
set -euo pipefail
umask 077
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/var/tmp}/flake-cache-test.XXXXXXXX")
runtime=$(mktemp -d "${RUNTIME_DIRECTORY:-/dev/shm}/flake-cache-test.XXXXXXXX")
trap 'rm -rf -- "$work" "$runtime"' EXIT
export RUNTIME_DIRECTORY="$runtime" SOPS_AGE_KEY_FILE="$runtime/age.key" TEST_CLOUD="$work/cloud"
mkdir "$work/bin" "$TEST_CLOUD"
cat > "$work/bin/gcloud" <<'PY'
#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import sys

root = Path(os.environ['TEST_CLOUD'])


def path(value):
    return root / value.removeprefix('gs://') if value.startswith('gs://') else Path(value)


def write(src, dest, immutable=False):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if immutable and dest.exists():
        sys.exit(1)
    shutil.copyfile(src, dest)


args = sys.argv[1:]
assert args[0] == 'storage', args
op, first = args[1:3]
if op == 'cat':
    sys.stdout.buffer.write(path(first).read_bytes())
elif op == 'cp':
    write(path(first), path(args[3]), '--if-generation-match=0' in args)
elif op == 'rsync':
    assert '--no-clobber' in args and '--if-generation-match=0' in args, args
    src, dest = path(first), path(args[3])
    if (root / 'fail-upload').exists():
        sys.exit(1)
    for item in src.rglob('*'):
        if item.is_file() and not (dest / item.relative_to(src)).exists():
            write(item, dest / item.relative_to(src), immutable=True)
else:
    raise SystemExit(f'unexpected command: {args}')
PY
chmod 700 "$work/bin/gcloud"
export PATH="$work/bin:$PATH"
age-keygen -o "$SOPS_AGE_KEY_FILE" 2>/dev/null
recipient=$(age-keygen -y "$SOPS_AGE_KEY_FILE")
mkdir "$TEST_CLOUD/signing-bucket"
nix key generate-secret --key-name flake-public-cache-7 > "$runtime/private"
public=$(nix key convert-secret-to-public < "$runtime/private")
# Keep the smoke-test signing material on tmpfs too.
jq -Rs '{signing_key: rtrimstr("\n")}' < "$runtime/private" > "$runtime/in.json"
sops --config /dev/null encrypt --age "$recipient" --output-type json "$runtime/in.json" \
  > "$TEST_CLOUD/signing-bucket/cache-signing.sops.json"
rm -- "$runtime/private" "$runtime/in.json"
for host in nixos-desktop nixos-spin713; do
  src="$work/nixos-system-$host-demo"
  mkdir -p "$src/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$src/bin/switch-to-configuration"
  chmod +x "$src/bin/switch-to-configuration"
done
desktop=$(nix-store --add "$work/nixos-system-nixos-desktop-demo")
spin=$(nix-store --add "$work/nixos-system-nixos-spin713-demo")
sha=0101010101010101010101010101010101010101
manifest="$TEST_CLOUD/cache-bucket/releases/$sha.json"
args=(gs://cache-bucket gs://signing-bucket/cache-signing.sops.json "$sha" "$desktop" "$spin")
# A transfer failure must not publish the release marker or leave decrypted material.
touch "$TEST_CLOUD/fail-upload"
if bash "$repo/scripts/ci/publish-cache.sh" "${args[@]}"; then
  echo 'publish unexpectedly succeeded after transfer failure' >&2
  exit 1
fi
[[ ! -e $manifest && ! -e $TEST_CLOUD/cache-bucket/channels/stable.json ]]
[[ $(find "$runtime" -maxdepth 1 -type f -printf '%f\n') == age.key ]]
rm -- "$TEST_CLOUD/fail-upload"

bash "$repo/scripts/ci/publish-cache.sh" "${args[@]}"
cache="$TEST_CLOUD/cache-bucket/cache/flake-public-cache-7"
jq -e --arg sha "$sha" --arg key "$public" --arg desktop "$desktop" --arg spin "$spin" \
  '.commit == $sha and .signing_public_key == $key and .hosts == {"nixos-desktop":$desktop,"nixos-spin713":$spin}' "$manifest" >/dev/null
for closure in "$desktop" "$spin"; do
  name=${closure##*/}
  grep -Fq 'Sig: flake-public-cache-7:' "$cache/${name%%-*}.narinfo"
done
# Require the test key's signature on both outputs and verify the archived NARs.
nix store verify --store "file://$cache" --sigs-needed 1 --option trusted-public-keys "$public" "$desktop" "$spin"
bash "$repo/scripts/ci/publish-cache.sh" "${args[@]}"
[[ $(find "$runtime" -maxdepth 1 -type f -printf '%f\n') == age.key ]]
[[ ! -e $TEST_CLOUD/cache-bucket/channels/stable.json ]]

# Do not replace a conflicting manifest even on retry.
jq '.hosts["nixos-spin713"] = "conflict"' "$manifest" > "$work/conflict.json"
cp -- "$work/conflict.json" "$manifest"
if bash "$repo/scripts/ci/publish-cache.sh" "${args[@]}"; then
  echo 'publish unexpectedly replaced a conflicting manifest' >&2
  exit 1
fi
cmp -- "$work/conflict.json" "$manifest"
[[ $(find "$runtime" -maxdepth 1 -type f -printf '%f\n') == age.key ]]
