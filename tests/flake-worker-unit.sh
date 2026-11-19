#!/usr/bin/env bash
# Verify the realised service closure rather than the Nix source text.
set -euo pipefail
system=${1:?pass the realised flake-cache-worker toplevel path}
unit="$system/etc/systemd/system/flake-cache-worker.service"
publisher=$(sed -n 's/^Environment="PUBLISH_CACHE=\([^" ]*\)"$/\1/p' "$unit")
if [[ ! $publisher =~ ^/nix/store/[^/]+/bin/flake-publish-cache$ || ! -x $publisher ]]; then
  echo 'The worker publisher is not an executable Nix store dependency.' >&2
  exit 1
fi
closure=$(nix-store --query --requisites "$system")
grep -Fxq -- "${publisher%/bin/*}" <<< "$closure"
# Do not borrow PATH dependencies from the machine that built the worker.
env -i "$publisher" --self-check
printf 'Worker publisher is executable, self-contained, and retained by the system closure.\n'
