#!/usr/bin/env bash
set -euo pipefail
umask 077
export HOME=$STATE_DIRECTORY
export CLOUDSDK_CONFIG=$STATE_DIRECTORY/gcloud
# The full boot disk and store persist across runs; only /run contains decrypted material.
export SOPS_AGE_KEY_FILE=$STATE_DIRECTORY/age.key
if [[ ! -e $SOPS_AGE_KEY_FILE ]]; then
  age-keygen -o "$SOPS_AGE_KEY_FILE" 2>/dev/null
fi
printf 'FLAKE_CACHE_AGE_RECIPIENT=%s\n' "$(age-keygen -y "$SOPS_AGE_KEY_FILE")"
project_number=$(curl -fsS --max-time 20 -H 'Metadata-Flavor: Google' \
  http://169.254.169.254/computeMetadata/v1/project/numeric-project-id)
[[ $project_number =~ ^[0-9]+$ ]]
cache=gs://flake-public-cache-$project_number
signing=gs://flake-public-signing-$project_number/cache-signing.sops.json
request=$RUNTIME_DIRECTORY/request.json
if ! gcloud storage cat "$cache/requests/pending.json" > "$request"; then
  echo 'FLAKE_CACHE_IDLE: no readable request; no build started'
  exit 0
fi
sha=$(jq -er '.commit | select(type == "string" and test("^[0-9a-f]{40}$"))' "$request")
run=$(jq -er '.run | select(type == "string" and test("^[0-9]+-[0-9]+$"))' "$request")
mode=$(jq -er '(.mode // "build") | select(. == "build" or . == "update-worker")' "$request")
[[ $sha =~ ^[0-9a-f]{40}$ && $run =~ ^[0-9]+-[0-9]+$ ]]
status="$cache/status/$run.json"
progress_prefix="$cache/releases/progress/$sha"
write_progress() {
  local name=$1
  local body=$2
  local tmp="$RUNTIME_DIRECTORY/progress-$name.json"
  printf '%s\n' "$body" > "$tmp"
  gcloud storage cp "$tmp" "$progress_prefix/$name.json" \
    --content-type=application/json --if-generation-match=0 --quiet >/dev/null 2>&1 || true
}
finish() {
  local rc=$?
  trap - EXIT
  if (( rc != 0 )) && [[ $mode == build ]]; then
    write_progress 99-failed "$(jq -cn --arg commit "$sha" --arg run "$run" --argjson exit_code "$rc" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{phase:"failed",commit:$commit,run:$run,exit_code:$exit_code,at:$at}')"
  fi
  jq -n --arg commit "$sha" --arg mode "$mode" --argjson exit_code "$rc" \
    '{commit:$commit,mode:$mode,exit_code:$exit_code}' \
    > "$RUNTIME_DIRECTORY/status.json"
  if ! gcloud storage cp "$RUNTIME_DIRECTORY/status.json" "$status" --quiet --if-generation-match=0; then
    printf 'FLAKE_CACHE_STATUS_UPLOAD_FAILED %s\n' "$run" >&2
  fi
  printf 'FLAKE_CACHE_END run=%s mode=%s rc=%s\n' "$run" "$mode" "$rc"
  systemctl --no-block poweroff || true
  exit "$rc"
}
trap finish EXIT
if [[ $mode == build ]]; then
  if [[ ! ${PUBLISH_CACHE:-} =~ ^/nix/store/[^/]+/bin/flake-publish-cache$ || ! -x $PUBLISH_CACHE ]]; then
    printf 'FLAKE_CACHE_PREFLIGHT_FAILED: publisher must be an executable Nix store path\n' >&2
    exit 127
  fi
  if ! "$PUBLISH_CACHE" --self-check; then
    printf 'FLAKE_CACHE_PREFLIGHT_FAILED: publisher dependency check failed\n' >&2
    exit 127
  fi
  printf 'FLAKE_CACHE_PREFLIGHT_OK run=%s\n' "$run"
  write_progress 01-checkout "$(jq -cn --arg commit "$sha" --arg run "$run" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{phase:"checkout",commit:$commit,run:$run,at:$at}')"
fi
build_home=/var/lib/flake-build
as_builder() { runuser -u flake-build -- env HOME="$build_home" "$@"; }
checkout=$build_home/flake_public
if [[ ! -d $checkout/.git ]]; then
  as_builder git clone --no-tags --single-branch --branch main https://github.com/khimoo/flake_public.git "$checkout"
fi
as_builder git -C "$checkout" fetch --no-tags https://github.com/khimoo/flake_public.git refs/heads/main
# Only build a revision of main, not a branch or arbitrary externally supplied code.
as_builder git -C "$checkout" merge-base --is-ancestor "$sha" FETCH_HEAD
as_builder git -C "$checkout" checkout --detach --force "$sha"

if [[ $mode == update-worker ]]; then
  printf 'FLAKE_CACHE_WORKER_UPDATE run=%s commit=%s\n' "$run" "$sha"
  root_dir=$build_home/worker-updates/$sha
  as_builder mkdir -p "$root_dir"
  cd "$checkout"
  worker_top=$(as_builder nix build --impure --out-link "$root_dir/toplevel" --print-out-paths --expr '
    let f = builtins.getFlake ("path:" + toString ./.); in
    (f.inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./hosts/flake-cache-worker/image.nix ];
    }).config.system.build.toplevel')
  [[ $worker_top =~ ^/nix/store/[0-9a-z]{32}-nixos-system-flake-cache-worker-[a-zA-Z0-9.\+-]+$ ]]
  [[ -x $worker_top/bin/switch-to-configuration ]]

  unit="$worker_top/etc/systemd/system/flake-cache-worker.service"
  [[ -r $unit ]]
  new_publisher=''
  pub_re='^Environment="PUBLISH_CACHE=([^"[:space:]]+)"$'
  while IFS= read -r line; do
    if [[ $line =~ $pub_re ]]; then
      new_publisher=${BASH_REMATCH[1]}
      break
    fi
  done < "$unit"
  if [[ ! $new_publisher =~ ^/nix/store/[^/]+/bin/flake-publish-cache$ || ! -x $new_publisher ]]; then
    printf 'FLAKE_CACHE_WORKER_UPDATE_FAILED: invalid PUBLISH_CACHE in new unit\n' >&2
    exit 1
  fi
  publisher_store=${new_publisher%/bin/*}
  closure_file="$RUNTIME_DIRECTORY/worker-closure.paths"
  as_builder nix path-info --recursive "$worker_top" > "$closure_file"
  found_publisher=0
  while IFS= read -r store_path; do
    if [[ $store_path == "$publisher_store" ]]; then
      found_publisher=1
      break
    fi
  done < "$closure_file"
  if (( ! found_publisher )); then
    printf 'FLAKE_CACHE_WORKER_UPDATE_FAILED: publisher missing from worker closure\n' >&2
    exit 1
  fi
  as_builder env -i "$new_publisher" --self-check

  cd "$STATE_DIRECTORY"
  nix-env -p /nix/var/nix/profiles/system --set "$worker_top"
  "$worker_top/bin/switch-to-configuration" boot
  printf 'FLAKE_CACHE_WORKER_UPDATED run=%s commit=%s toplevel=%s\n' "$run" "$sha" "$worker_top"
  exit 0
fi

printf 'FLAKE_CACHE_BUILD run=%s commit=%s\n' "$run" "$sha"
root_dir=$build_home/releases/$sha
as_builder mkdir -p "$root_dir"
cd "$checkout"
write_progress 02-build-desktop "$(jq -cn --arg commit "$sha" --arg run "$run" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{phase:"build-desktop",commit:$commit,run:$run,at:$at}')"
desktop=$(as_builder nix build --no-update-lock-file --out-link "$root_dir/desktop" \
  --print-out-paths .#nixosConfigurations.nixos-desktop.config.system.build.toplevel)
write_progress 03-build-spin713 "$(jq -cn --arg commit "$sha" --arg run "$run" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{phase:"build-spin713",commit:$commit,run:$run,at:$at}')"
spin=$(as_builder nix build --no-update-lock-file --out-link "$root_dir/spin713" \
  --print-out-paths .#nixosConfigurations.nixos-spin713.config.system.build.toplevel)
cd "$STATE_DIRECTORY"
"$PUBLISH_CACHE" "$cache" "$signing" "$sha" "$desktop" "$spin"
