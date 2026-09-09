#!/usr/bin/env bash
# Run from any directory. This never switches a system or a home generation.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 scripts/check-docs.py .
# Spin713's audio workaround uses system.replaceDependencies (IFD). Generate
# its reference derivations before flake check's read-only evaluation.
nix eval --option eval-cache false --json --no-update-lock-file .#nixosConfigurations \
  --apply 'hosts: builtins.mapAttrs (_: h: h.config.system.build.toplevel.drvPath) hosts'
printf '\n'
nix flake check --no-build --no-update-lock-file
# homeConfigurations are not covered by the standard flake output schema.
nix eval --json --no-update-lock-file .#homeConfigurations \
  --apply 'homes: builtins.mapAttrs (_: h: h.activationPackage.drvPath) homes'
printf '\n'
# Both platforms are evaluated; only the native builder is executed below.
nix eval --json --no-update-lock-file .#checks \
  --apply 'systems: builtins.mapAttrs (_: checks: builtins.mapAttrs (_: c: c.drvPath) checks) systems'
printf '\n'
check_system=$(nix eval --impure --raw --expr builtins.currentSystem)
nix build --no-link --no-update-lock-file ".#checks.${check_system}.module-contracts" ".#checks.${check_system}.docs" ".#checks.${check_system}.activation"
git diff --check
