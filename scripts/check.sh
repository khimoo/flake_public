#!/usr/bin/env bash
# Run from any directory. This never switches a system or a home generation.
#
#   check.sh          documents, light evaluation of every host and home, common checks
#   check.sh --all    also the host- and feature-specific checks
#   check.sh --full   also toplevel evaluation, nix flake check and every system's checks (CI)
#
# Which check belongs to which set is defined next to the check in tests/default.nix (checkSet).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mode=${1:-}
case $mode in
  "" | --all | --full) ;;
  *)
    echo "usage: $0 [--all | --full]" >&2
    exit 2
    ;;
esac

nix_eval() {
  nix eval --json --no-update-lock-file "$@"
  printf '\n'
}

python3 scripts/check-docs.py .

# system.path and the assertions do not go through the mutter patch's system.replaceDependencies,
# so they evaluate without building the patched mutter (import-from-derivation).
nix_eval .#nixosConfigurations --apply 'hosts: builtins.mapAttrs (_: h: {
  failed = map (a: a.message) (builtins.filter (a: !a.assertion) h.config.assertions);
  path = h.config.system.path.drvPath;
}) hosts'
# homeConfigurations are not covered by the standard flake output schema.
nix_eval .#homeConfigurations --apply 'homes: builtins.mapAttrs (_: h: h.activationPackage.drvPath) homes'

if [ "$mode" = --full ]; then
  # Generate the replaceDependencies reference derivations before flake check's read-only evaluation.
  nix eval --option eval-cache false --json --no-update-lock-file .#nixosConfigurations \
    --apply 'hosts: builtins.mapAttrs (_: h: h.config.system.build.toplevel.drvPath) hosts'
  printf '\n'
  nix flake check --no-build --no-update-lock-file
  # Both platforms are evaluated; only the native builder is executed below.
  nix_eval .#checks --apply 'systems: builtins.mapAttrs (_: checks: builtins.mapAttrs (_: c: c.drvPath) checks) systems'
fi

check_system=$(nix eval --impure --raw --expr builtins.currentSystem)
if [ "$mode" = "" ]; then
  sets='[ "common" ]'
else
  sets='[ "common" "feature" ]'
fi
mapfile -t checks < <(
  nix eval --json --no-update-lock-file ".#checks.${check_system}" \
    --apply "cs: builtins.attrNames (builtins.removeAttrs cs (builtins.filter (n: !(builtins.elem cs.\${n}.checkSet ${sets})) (builtins.attrNames cs)))" \
    | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)))'
)
nix build --no-link --no-update-lock-file "${checks[@]/#/.#checks.${check_system}.}"

git diff --check
