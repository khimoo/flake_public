#!/usr/bin/env bash
# Test real Nix/SOPS operations, with an isolated directory acting as Cloud Storage.
set -euo pipefail
umask 077
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/var/tmp}/flake-cache-test.XXXXXXXX")
runtime=$(mktemp -d "${RUNTIME_DIRECTORY:-/dev/shm}/flake-cache-test.XXXXXXXX")
trap 'rm -rf -- "$work" "$runtime"' EXIT
export RUNTIME_DIRECTORY="$runtime" SOPS_AGE_KEY_FILE="$runtime/age.key" TEST_CLOUD="$work/cloud" TEST_CLOUD_LOG="$work/uploads.log"
mkdir "$work/bin" "$TEST_CLOUD"
cat > "$work/bin/gcloud" <<'PY'
#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import sys

root = Path(os.environ['TEST_CLOUD'])
log_path = Path(os.environ['TEST_CLOUD_LOG'])


def path(value):
    return root / value.removeprefix('gs://') if value.startswith('gs://') else Path(value)


def write(src, dest, immutable=False):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if immutable and dest.exists():
        sys.exit(1)
    shutil.copyfile(src, dest)


def log_upload(dest):
    with log_path.open('a', encoding='utf-8') as f:
        f.write(str(dest.relative_to(root)) + '\n')


args = sys.argv[1:]
assert args[0] == 'storage', args
op = args[1]
pos = [a for a in args[2:] if not a.startswith('-')]
if op == 'cat':
    sys.stdout.buffer.write(path(pos[0]).read_bytes())
elif op == 'ls':
    uri = pos[0].rstrip('/')
    target_dir = path(uri)
    entries = sorted(target_dir.iterdir()) if target_dir.is_dir() else []
    if not entries:
        print('ERROR: (gcloud.storage.ls) One or more URLs matched no objects.', file=sys.stderr)
        sys.exit(1)
    for entry in entries:
        suffix = '/' if entry.is_dir() else ''
        print(f'{uri}/{entry.name}{suffix}')
elif op == 'cp':
    sources, dest_arg = pos[:-1], pos[-1]
    no_clobber = '--no-clobber' in args
    immutable = '--if-generation-match=0' in args
    if dest_arg.startswith('gs://') and (root / 'fail-upload').exists():
        sys.exit(1)
    if dest_arg.endswith('/'):
        dest_dir = path(dest_arg.rstrip('/'))
        for src in sources:
            src_path = path(src)
            target = dest_dir / src_path.name
            if no_clobber and target.exists():
                continue
            write(src_path, target, immutable=immutable)
            if dest_arg.startswith('gs://'):
                log_upload(target)
    else:
        assert len(sources) == 1, args
        target = path(dest_arg)
        if not (no_clobber and target.exists()):
            write(path(sources[0]), target, immutable=immutable)
            if dest_arg.startswith('gs://'):
                log_upload(target)
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

: > "$TEST_CLOUD_LOG"
bash "$repo/scripts/ci/publish-cache.sh" "${args[@]}"
cache="$TEST_CLOUD/cache-bucket/cache/flake-public-cache-7"
jq -e --arg sha "$sha" --arg key "$public" --arg desktop "$desktop" --arg spin "$spin" \
  '.commit == $sha and .signing_public_key == $key and .hosts == {"nixos-desktop":$desktop,"nixos-spin713":$spin}' "$manifest" >/dev/null
# NAR payloads must be uploaded before any .narinfo that references them.
python3 - "$TEST_CLOUD_LOG" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding='utf-8').splitlines()
nar_idx = [i for i, l in enumerate(lines) if '/nar/' in l]
info_idx = [i for i, l in enumerate(lines) if l.endswith('.narinfo')]
assert nar_idx and info_idx, lines
assert max(nar_idx) < min(info_idx), lines
PY
for closure in "$desktop" "$spin"; do
  name=${closure##*/}
  grep -Fq 'Sig: flake-public-cache-7:' "$cache/${name%%-*}.narinfo"
done
# Require the test key's signature on both outputs and verify the archived NARs.
nix store verify --store "file://$cache" --sigs-needed 1 --option trusted-public-keys "$public" "$desktop" "$spin"

# Repeating an identical publish skips re-uploading already-published store paths.
: > "$TEST_CLOUD_LOG"
bash "$repo/scripts/ci/publish-cache.sh" "${args[@]}"
[[ ! -s $TEST_CLOUD_LOG ]]
[[ $(find "$runtime" -maxdepth 1 -type f -printf '%f\n') == age.key ]]
[[ ! -e $TEST_CLOUD/cache-bucket/channels/stable.json ]]

# Publishing a new commit where only one host changed uploads only the new store path.
src2="$work/nixos-system-nixos-spin713-demo2"
mkdir -p "$src2/bin"
printf '#!/usr/bin/env bash\n# v2\nexit 0\n' > "$src2/bin/switch-to-configuration"
chmod +x "$src2/bin/switch-to-configuration"
spin2=$(nix-store --add "$src2")
sha2=0202020202020202020202020202020202020202
: > "$TEST_CLOUD_LOG"
bash "$repo/scripts/ci/publish-cache.sh" gs://cache-bucket gs://signing-bucket/cache-signing.sops.json "$sha2" "$desktop" "$spin2"
desktop_name=${desktop##*/}
spin2_name=${spin2##*/}
! grep -Fq "${desktop_name%%-*}.narinfo" "$TEST_CLOUD_LOG"
grep -Fq "${spin2_name%%-*}.narinfo" "$TEST_CLOUD_LOG"
nix store verify --store "file://$cache" --sigs-needed 1 --option trusted-public-keys "$public" "$desktop" "$spin2"

# Do not replace a conflicting manifest even on retry.
jq '.hosts["nixos-spin713"] = "conflict"' "$manifest" > "$work/conflict.json"
cp -- "$work/conflict.json" "$manifest"
if bash "$repo/scripts/ci/publish-cache.sh" "${args[@]}"; then
  echo 'publish unexpectedly replaced a conflicting manifest' >&2
  exit 1
fi
cmp -- "$work/conflict.json" "$manifest"
[[ $(find "$runtime" -maxdepth 1 -type f -printf '%f\n') == age.key ]]
