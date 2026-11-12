def _quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

def user_config(user, incoming):
    items = []
    by_path = {}
    ssh_keys = {}
    for w in incoming:
        item = dict(w.value)
        explicit_key = item.pop("ssh_key", False)
        item.setdefault("mode", "600")
        path = item["path"]
        if not path.startswith(user.home + "/") or ".." in path.split("/"):
            fail("secrets: secret destinations must live below the user's home")
        if path in by_path and (explicit_key or path in ssh_keys):
            fail("secrets: duplicate SSH key filename")
        if explicit_key:
            ssh_keys[path] = True
        if path in by_path:
            if by_path[path] != item:
                fail("secrets: duplicate secret destination")
        else:
            by_path[path] = item
            items.append(item)
    extract_template = "dest=PATH_PLACEHOLDER\nif [ -L \"$dest\" ] || { [ -e \"$dest\" ] && [ ! -f \"$dest\" ]; }; then\n  echo \"secrets: $dest: 通常のファイルでないので触らない\" >&2\nelse\n  mkdir -p \"$(dirname \"$dest\")\"\n  pending_tmp=$(umask 077; mktemp \"$dest.XXXXXX\")\n  if ! ( umask 077\n         SOPS_AGE_KEY_FILE=\"$age_key\" \\\n           SOPS_PLACEHOLDER --decrypt --extract SELECTOR_PLACEHOLDER \"$secrets\" < /dev/null > \"$pending_tmp\" ); then\n    echo \"secrets: SECRET_PLACEHOLDER の復号に失敗した。$age_key がこの暗号文の受信者か確認する\" >&2\n    exit 1\n  fi\n  if [ -f \"$dest\" ] && cmp -s -- \"$pending_tmp\" \"$dest\"; then\n    chmod MODE_PLACEHOLDER \"$dest\"\n  else\n    chmod MODE_PLACEHOLDER \"$pending_tmp\"\n    mv -f -- \"$pending_tmp\" \"$dest\"\n  fi\n  rm -f -- \"$pending_tmp\"\n  pending_tmp=\n  printf '%s\\n' \"$dest\" >> \"$state_tmp\"\nfi\n"
    extracts = []
    for item in items:
        text = extract_template.replace("PATH_PLACEHOLDER", _quote(item["path"]))
        text = text.replace("MODE_PLACEHOLDER", _quote(item["mode"])).replace("SECRET_PLACEHOLDER", item["secret"])
        before, after = text.split("SOPS_PLACEHOLDER")
        selector, tail = after.split("SELECTOR_PLACEHOLDER")
        extracts.append(concat(before, exe("sops", "sops"), selector, "'", toJSON([item["secret"]]), "'", tail))
    key_block = ""
    if items:
        text = "age_key=AGE_KEY_PLACEHOLDER\n# 暗号文を単独で store にコピーし、世代の closure に入れる。起動時の activation も毎回復号するので、\n# GC で flake のソースが消えても読めるようにする。\nsecrets=SECRETS_FILE_PLACEHOLDER\nif [ -z \"$dry_run\" ] && [ ! -f \"$age_key\" ]; then\n  echo \"secrets: age 復号鍵 $age_key が無い。\" >&2\necho \"  既存マシンから送る: ( umask 077; ssh <既存機> 'cat ~/.config/sops/age/keys.txt' > $age_key )\" >&2\necho \"  または Bitwarden から取り出して同じパスに 600 で置く。\" >&2\n  exit 1\nfi\n"
        text = text.replace("AGE_KEY_PLACEHOLDER", _quote(user.home + "/.config/sops/age/keys.txt"))
        before, after = text.split("SECRETS_FILE_PLACEHOLDER")
        key_block = concat(before, "'", repoPath("secrets/secrets.yaml"), "'", after)
    text = "(\n  state_file=STATE_FILE_PLACEHOLDER\n  declared=(DECLARED_PLACEHOLDER)\n  dry_run=${DRY_RUN_CMD:-}\n  KEY_BLOCK_PLACEHOLDER\n  # 空の宣言で記録も無い場合は、ディレクトリすら作らない。\n  if [ \"${#declared[@]}\" = 0 ] && [ ! -f \"$state_file\" ]; then\n    exit 0\n  fi\n  pending_tmp=\n  state_tmp=\n  trap 'rm -f -- \"$pending_tmp\" \"$state_tmp\"' EXIT\n  trap 'exit 1' HUP INT TERM\n  if [ -n \"$dry_run\" ]; then\n    for dest in \"${declared[@]}\"; do\n      echo \"secrets: (dry-run) $dest を暗号文に揃える予定\" >&2\n    done\n  else\n    mkdir -p \"$(dirname \"$state_file\")\"\n    state_tmp=$(umask 077; mktemp \"$state_file.XXXXXX\")\n    EXTRACT_PLACEHOLDER\n  fi\n  if [ -f \"$state_file\" ]; then\n    while IFS= read -r dest; do\n      is_declared=\n      for path in \"${declared[@]}\"; do\n        if [ \"$dest\" = \"$path\" ]; then\n          is_declared=1\n          break\n        fi\n      done\n      [ -z \"$is_declared\" ] || continue\n      if [ -n \"$dry_run\" ]; then\n        echo \"secrets: (dry-run) $dest: 宣言から外れたので削除予定\" >&2\n      elif [ -L \"$dest\" ] || { [ -e \"$dest\" ] && [ ! -f \"$dest\" ]; }; then\n        echo \"secrets: $dest: 通常のファイルでないので削除せず記録から外す\" >&2\n      else\n        rm -f -- \"$dest\"\n      fi\n    done < \"$state_file\"\n  fi\n  if [ -z \"$dry_run\" ]; then\n    mv -f -- \"$state_tmp\" \"$state_file\"\n    state_tmp=\n  fi\n)\n"
    text = text.replace("STATE_FILE_PLACEHOLDER", _quote(user.home + "/.local/state/flake-secrets/placed"))
    text = text.replace("DECLARED_PLACEHOLDER", " ".join([_quote(i["path"]) for i in items]))
    before, after = text.split("KEY_BLOCK_PLACEHOLDER")
    middle, tail = after.split("EXTRACT_PLACEHOLDER")
    body = concat(*([before, key_block, middle] + extracts + [tail]))
    return {"home": {
        "home.activation.secrets": activation(["writeBoundary"], body),
    }}
