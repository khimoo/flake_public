#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z $1 ]]; then
  printf 'Usage: %s <out.html>\n' "${0##*/}" >&2
  exit 1
fi

repo=$(git rev-parse --show-toplevel)
out=$1
[[ $out = /* ]] || out=$PWD/$out

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
[[ $work = /* ]] || work=$PWD/$work

confgen() (
  cd "$repo/tools/confgen"
  nix shell nixpkgs#go -c go run . "$@"
)

nix_string() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//\${/\\\${}
  printf '"%s"' "$value"
}

confgen graph-options "$repo/config" > "$work/options.json"
nix eval --impure --json --expr "
  import (builtins.toPath $(nix_string "$repo/tools/confgen/final-values.nix")) {
    flakeRef = $(nix_string "git+file://$repo");
    optionsFile = $(nix_string "$work/options.json");
  }
" > "$work/final.json"
confgen graph "$repo/config" "$work/final.json" "$out"
