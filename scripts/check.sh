#!/usr/bin/env bash
# Run from any directory. This never switches a system or a home generation.
#
#   check.sh          documents, Go tests, and the hosts and checks affected by the changed files
#   check.sh --all    every host and every check
#   check.sh --full   also toplevel evaluation, nix flake check and every system's checks (CI)
#
# How changed files map to checks: docs/howtouse/validation.md.
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

pkgs_expr='(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.${builtins.currentSystem}'
go_package=$(nix build --no-link --print-out-paths --no-update-lock-file --impure \
  --expr "let pkgs = ${pkgs_expr}; in pkgs.go")

changed=()
if [ "$mode" = "" ]; then
  changed_file=$(mktemp)
  trap 'rm -f "$changed_file"' EXIT
  if base=$(git merge-base HEAD '@{upstream}' 2>/dev/null); then
    git diff --name-only -z "$base" >> "$changed_file"
  fi
  git diff --name-only -z HEAD >> "$changed_file"
  git diff --name-only -z --cached >> "$changed_file"
  git ls-files --others --exclude-standard -z >> "$changed_file"
  sort -zu "$changed_file" -o "$changed_file"
  mapfile -d '' -t changed < "$changed_file"
  rm -f "$changed_file"
  trap - EXIT
fi

affected='{"elements": [], "hosts": []}'
if [ "$mode" != "" ]; then
  affected='{"elements": ["ALL"], "hosts": []}'
elif (( ${#changed[@]} )); then
  confgen_package=$(nix build --no-link --print-out-paths --no-update-lock-file --impure \
    --expr "(import ./lib/confgen.nix { pkgs = ${pkgs_expr}; }).package")
  affected=$("$confgen_package/bin/confgen" affected "$PWD" "${changed[@]}")
fi

checks=()
selected_hosts='[]'
if [ "$mode" != "" ] || (( ${#changed[@]} )); then
  metadata=$(nix eval --impure --json --no-update-lock-file --expr \
    "let f = builtins.getFlake (toString ./.); in {
      checks = builtins.mapAttrs (_: c: {
        elements = c.elements or [];
        hosts = c.hosts or [];
        always = c.always or false;
      }) f.checks.\${builtins.currentSystem};
      hosts = builtins.attrNames f.nixosConfigurations ++ builtins.attrNames f.homeConfigurations;
    }")
  selection=$(python3 - "$affected" "$metadata" <<'PY'
import json
import sys

affected, metadata = map(json.loads, sys.argv[1:])
untagged = [name for name, tags in metadata["checks"].items()
            if not (tags["elements"] or tags["hosts"] or tags["always"])]
if untagged:
    sys.exit("Checks without tags: " + ", ".join(sorted(untagged)))
elements = set(affected["elements"] or [])
all_checks = elements == {"ALL"}
hosts = set(metadata["hosts"] if all_checks else affected["hosts"] or [])
checks = [name for name, tags in metadata["checks"].items()
          if all_checks or tags["always"] or elements.intersection(tags["elements"])
          or hosts.intersection(tags["hosts"])]
print(json.dumps({"elements": sorted(elements), "hosts": sorted(hosts), "checks": sorted(checks)}))
PY
  )
  selected_hosts=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["hosts"]))' "$selection")
  check_names=$(python3 -c 'import json,sys; print("\n".join(json.loads(sys.argv[1])["checks"]))' "$selection")
  if [ -n "$check_names" ]; then
    mapfile -t checks <<< "$check_names"
  fi
else
  selection='{"elements": [], "hosts": [], "checks": []}'
fi
python3 - "$selection" <<'PY'
import json
import sys

for kind, names in json.loads(sys.argv[1]).items():
    print(f"{kind}: {' '.join(names) if names else '(none)'}")
PY

python3 scripts/check-docs.py .
(cd tools/confgen && "$go_package/bin/go" test ./...)

if [ "$selected_hosts" != '[]' ]; then
  # system.path avoids the mutter replacement's import-from-derivation build.
  nix_eval .#nixosConfigurations --apply "hosts: builtins.mapAttrs (name: h:
    let
      failed = map (a: a.message) (builtins.filter (a: !a.assertion) h.config.assertions);
    in
      if failed != [] then
        throw (\"Host \" + name + \" failed assertions:\\n\" + builtins.concatStringsSep \"\\n\" failed)
      else { path = h.config.system.path.drvPath; }
  ) (builtins.intersectAttrs (builtins.listToAttrs (map (name: { inherit name; value = null; }) (builtins.fromJSON ''${selected_hosts}''))) hosts)"
  nix_eval .#homeConfigurations --apply "homes: builtins.mapAttrs (_: h: h.activationPackage.drvPath)
    (builtins.intersectAttrs (builtins.listToAttrs (map (name: { inherit name; value = null; }) (builtins.fromJSON ''${selected_hosts}''))) homes)"
fi

if [ "$mode" = --full ]; then
  # flake check needs the reference derivations created by replaceDependencies first.
  nix eval --option eval-cache false --json --no-update-lock-file .#nixosConfigurations \
    --apply 'hosts: builtins.mapAttrs (_: h: h.config.system.build.toplevel.drvPath) hosts'
  printf '\n'
  nix flake check --no-build --no-update-lock-file
  nix_eval .#checks --apply 'systems: builtins.mapAttrs (_: cs: builtins.mapAttrs (_: c: c.drvPath) cs) systems'
fi

if (( ${#checks[@]} )); then
  check_system=$(nix eval --impure --raw --expr builtins.currentSystem)
  nix build --no-link --no-update-lock-file "${checks[@]/#/.#checks.${check_system}.}"
fi

git diff --check
