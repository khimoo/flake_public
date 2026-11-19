#!/usr/bin/env bash
set -euo pipefail

if (( $# == 0 )); then
  printf 'Usage: bash %s <nixosConfiguration> [...]\n' "$0" >&2
  exit 2
fi

for host in "$@"; do
  printf 'Evaluating package set for %s\n' "$host"
  drv=$(nix eval --raw --no-update-lock-file \
    ".#nixosConfigurations.$host.config.system.path.drvPath")
  printf '%s\n' "$drv"
done
