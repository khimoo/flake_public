# cargo run と同じ引数でビルドを CARGO_REMOTE_RUN_HOST に任せ、できた実行ファイルを手元で実行する。
# 使い方は docs/howtouse/remote-build.md、設計判断は docs/architecture/remote-build.md。

# cargo のサブコマンドとして呼ばれると、先頭の引数にサブコマンド名が入る。
if [ "${1-}" = remote-run ]; then shift; fi

host=$CARGO_REMOTE_RUN_HOST
root=$(dirname "$(cargo locate-project --workspace --message-format plain)")
cwd=$(pwd -P)
rel_cwd=${cwd#"$root"}
state=$root/target/remote-run
remote_dir=.cache/cargo-remote-run/$(uname -n)$root
mkdir -p "$state/bin"

# direnv と同じく、いちばん近い .envrc の `use flake [ref]` を devShell とする。
envrc_dir=$cwd
until [ -f "$envrc_dir/.envrc" ]; do
  if [ "$envrc_dir" = / ]; then
    echo "cargo-remote-run: $cwd から上のディレクトリに .envrc がない" >&2
    exit 1
  fi
  envrc_dir=$(dirname "$envrc_dir")
done
if ! line=$(grep -m1 -E '^[[:space:]]*use[[:space:]]+flake([[:space:]]|$)' "$envrc_dir/.envrc"); then
  echo "cargo-remote-run: $envrc_dir/.envrc に use flake がない" >&2
  exit 1
fi
read -r _ _ ref _ <<<"$line"
ref=${ref//[\"\']/}

# 手元の devShell をそのままホストへ送ってビルドに使う。glibc やライブラリのストアパスが
# 手元と一致するので、持ち帰った実行ファイルが手元でそのまま動く。ホストにないパスは、
# 手元から送らずにホストが binary cache から取る。devShell の env は手元か常設ビルダーで
# ビルドしたもので署名がないので、署名の確認を省く（ホストで trusted-users のユーザーだけが省ける）。
(cd "$envrc_dir" && nix print-dev-env --profile "$state/dev-env" "${ref:-.}") >"$state/dev-env.rc"
nix copy --to "ssh-ng://$host" --substitute-on-destination --no-check-sigs "$(readlink -f "$state/dev-env")"

# 除外した target/ は --delete でも消えないので、ホスト側の incremental compilation の結果が残る。
rsync -a --delete --mkpath --exclude=/target/ --exclude=.git/ --exclude=.direnv/ \
  --filter=':- .gitignore' "$root/" "$host:$remote_dir/"

# どの実行ファイルを動かすか（default-run、-p、--bin、--example）は cargo run 自身に決めさせる。
# runner は実行する代わりに、ホスト側のワークスペース、CARGO_MANIFEST_DIR、実行ファイル、
# 実行時の引数を NUL 区切りで標準出力へ出す。
# shellcheck disable=SC2016
runner='target."cfg(all())".runner = ["sh", "-c", "printf \"%s\\0\" \"$CARGO_REMOTE_RUN_ROOT\" \"$CARGO_MANIFEST_DIR\" \"$@\"", "runner"]'

# 標準入力で受けた devShell の rc を読み込んでからビルドする。shellHook には `just --list` のように
# プロジェクトの外で失敗するものがあるので、rc はワークスペースの中で読み込む。rc は shellHook の
# 出力を標準出力に出すので捨て、標準出力を runner の出力だけにする。rc は一時ディレクトリを作って
# NIX_BUILD_TOP に入れるので、終了時に消す。引き継いだ NIX_BUILD_TOP を消さないよう、読み込む前に unset する。
remote_script=$(
  cat <<'EOF'
cd "$HOME/$1$2"
unset NIX_BUILD_TOP
. /dev/stdin >/dev/null
if [ -n "${NIX_BUILD_TOP-}" ]; then trap 'rm -rf "$NIX_BUILD_TOP"' EXIT; fi
export CARGO_REMOTE_RUN_ROOT=$HOME/$1
config=$3
shift 3
cargo run --config "$config" "$@" </dev/null
EOF
)
color=never
if [ -t 2 ]; then color=always; fi
# 引数は printf %q でエスケープしてから、ホストのログインシェル（bash）に渡す。
# shellcheck disable=SC2029
ssh "$host" "$(printf '%q ' env CARGO_TERM_COLOR="$color" bash -c "$remote_script" remote-run \
  "$remote_dir" "$rel_cwd" "$runner" "$@")" <"$state/dev-env.rc" >"$state/run-info"

mapfile -d '' -t info <"$state/run-info"
remote_root=${info[0]}
exe=${info[2]}
# cargo は cwd の下にある実行ファイルを cwd からの相対パスで渡す。
case $exe in
  /*) ;;
  *) exe=$remote_root$rel_cwd/$exe ;;
esac
# rsync は一時ファイルに書いてから置き換えるので、前回の実行ファイルを残すと、debug 情報付きの
# 大きな実行ファイル 2 つ分の空きが手元に要る。差分転送は使えなくなるが、先に消す。
rm -f "$state/bin/${exe##*/}"
rsync -a --compress "$host:$exe" "$state/bin/"

# Bevy などは CARGO_MANIFEST_DIR から assets/ を探すので、cargo run と同じく手元のパッケージを指す。
export CARGO_MANIFEST_DIR=$root${info[1]#"$remote_root"}
exec "$state/bin/${exe##*/}" "${info[@]:3}"
