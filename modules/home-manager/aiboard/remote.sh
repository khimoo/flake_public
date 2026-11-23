# SSH concatenates its command arguments. Quote each locally so the remote shell
# receives the original argument rather than evaluating forum text as shell code.
remote=${AIBOARD_SSH_HOST:-$AIBOARD_DEFAULT_SSH_HOST}
cmd='exec aiboard'
for arg; do
    escaped=${arg//\'/\'\\\'\'}
    cmd+=" '${escaped}'"
done
exec ssh -T -- "$remote" "$cmd"
