# sshfs 上では .direnv を手元の ~/.cache に置く。共有の .direnv には別の PC の
# /nix/store へのリンクが入り、nix-direnv が入るたびに作り直すため。
when = ["sshfs_editing", "direnv"]

_BEFORE_FINDMNT = """direnv_layout_dir() {
  if [[ -n ${direnv_layout_dir:-} ]]; then
    echo "$direnv_layout_dir"
  elif [[ $("""

_AFTER_FINDMNT = """ -n -o FSTYPE -T "$PWD") == fuse.sshfs ]]; then
    local hash
    hash=$(printf '%s' "$PWD" | sha1sum | cut -c1-40)
    echo "${XDG_CACHE_HOME:-$HOME/.cache}/direnv/layouts/$hash${PWD//[^a-zA-Z0-9]/-}"
  else
    echo "$PWD/.direnv"
  fi
}
"""

def writes(direnv, util_linux):
    return [write(direnv, concat(_BEFORE_FINDMNT, util_linux.findmnt, _AFTER_FINDMNT))]
