requires = ["secrets"]

def public(user):
    return {"github_secret": {"secret": "git_ssh_key", "path": user.home + "/.ssh/id_github", "mode": "600"}}

def _quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

def user_config(user, checkout, incoming):
    repos = [w.value for w in incoming]
    destinations = {}
    for repo in repos:
        if not repo["dest"].startswith(user.home + "/") or ".." in repo["dest"].split("/"):
            fail("private_repos: mutable checkouts must belong to this user's home directory")
        if repo["dest"] in destinations:
            fail("private_repos: duplicate clone destination")
        destinations[repo["dest"]] = True
    key = user.home + "/.ssh/id_github"
    ssh = concat(exe("openssh", "ssh"), " -i " + key + " -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new")
    clone_head = "dry_run=0\nif [ \"${1:-}\" = \"--dry-run\" ]; then\n  dry_run=1\nfi\n\nclone() {\n  local repo=$1 dest=$2 parent clone_tmp\n  if [ -e \"$dest\" ] || [ -L \"$dest\" ]; then\n    if [ ! -e \"$dest/.git\" ]; then\n      echo \"clone-repos: $dest exists but is not a Git checkout; inspect it before retrying\" >&2\n      return 1\n    fi\n    return 0\n  fi\n  if [ \"$dry_run\" = 1 ]; then\n    echo \"clone-repos: (dry-run) $repo を $dest へ clone する予定\" >&2\n    return 0\n  fi\n  parent=$(dirname \"$dest\")\n  if ! mkdir -p \"$parent\"; then\n    return 1\n  fi\n  if ! clone_tmp=$(mktemp -d \"$parent/.private-clone.XXXXXX\"); then\n    return 1\n  fi\n  if ! GIT_SSH_COMMAND=GIT_SSH_PLACEHOLDER git clone \"$repo\" \"$clone_tmp/repo\"; then\n    rm -rf -- \"$clone_tmp\"\n    return 1\n  fi\n  if [ -e \"$dest\" ] || [ -L \"$dest\" ]; then\n    rm -rf -- \"$clone_tmp\"\n    echo \"clone-repos: $dest appeared during clone; refusing to overwrite\" >&2\n    return 1\n  fi\n  if ! mv \"$clone_tmp/repo\" \"$dest\"; then\n    echo \"clone-repos: failed to move checkout to $dest\" >&2\n    rm -rf -- \"$clone_tmp\"\n    return 1\n  fi\n  rm -rf -- \"$clone_tmp\"\n}\n\nif [ \"$dry_run\" = 0 ] && [ ! -f KEY_QUOTED_PLACEHOLDER ]; then\n  echo \"clone-repos: KEY_PLACEHOLDER がない。switch で secrets が配置されたか確認する\" >&2\n  exit 1\nfi\n\nstatus=0\n"
    clone_tail = "\nexit \"$status\"\n"
    clone_head = clone_head.replace("KEY_QUOTED_PLACEHOLDER", _quote(key)).replace("KEY_PLACEHOLDER", key)
    before, after = clone_head.split("GIT_SSH_PLACEHOLDER")
    calls = "\n".join(["clone " + _quote(r["url"]) + " " + _quote(r["dest"]) + " || status=1" for r in repos])
    clone = shellApp("clone-repos", [pkg("git"), pkg("coreutils")], concat(before, "'", ssh, "'", after, calls, clone_tail))
    targets = [checkout.root]
    for repo in repos:
        if repo["dest"] not in targets:
            targets.append(repo["dest"])
    pull_text = """status=0
# 配列にしておくと、private repo がなく対象が flake 自身だけのときも shellcheck の SC2043 にならない。
targets=(""" + " ".join([_quote(p) for p in targets]) + """)
for dest in "${targets[@]}"; do
  if [ ! -e "$dest/.git" ]; then
    echo "pull-repos: $dest は clone されていない (clone-repos で clone する)" >&2
    status=1
    continue
  fi
  echo "==> $dest"
  git -C "$dest" pull --ff-only || status=1
done
exit "$status"
"""
    if repos:
        pull_text = concat("export GIT_SSH_COMMAND='", ssh, "'\n", pull_text)
    pull = shellApp("pull-repos", [pkg("git"), pkg("openssh")], pull_text)
    return {"home": {
        "home.packages": [pull] + ([clone] if repos else []),
    }}
